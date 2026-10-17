#!/usr/bin/env bash
# art-gen — one ImageRouter image per call: art-gen.sh <slot NN | pack:NAME | scene:NAME> [model] [seed]
# NN: prompts.yaml base + slot look + accent color. pack:NAME: one 4×3 sheet of 12 busts (prompts.yaml sheet +
# site/art/packs/NAME.yaml style + numbered slot looks/colors; art-pack.sh slices it). scene:NAME:
# site/art/scenes.yaml base.<kind> + scenes.NAME prompt.
# Jobs may override size/quality/est. Cache: site/art/raw/<sha256(model+prompt+size+seed)>.png;
# a cache hit never re-bills. Ledger: site/art/raw/ledger.tsv (ts model slot cost key). Paid calls refuse when
# ledger total + est ≥ budget. The key comes from scripts/keys.sh into env only — never argv, logs or names.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
[[ $# -ge 1 ]] || { echo "usage: art-gen.sh <NN|pack:NAME|scene:NAME> [model] [seed]" >&2; exit 2; }
slot=$1; model=${2:-openai/gpt-image-2:free}; seed=${3:-0}
# shellcheck source=keys.sh
source "$root/scripts/keys.sh"
load_key IMAGEROUTER_API_KEY "$IMAGEROUTER_KEY_FILE" || { echo "art-gen: no key — ask the human" >&2; exit 1; }
exec python3 -I - "$root" "$slot" "$model" "$seed" <<'PY'
import base64, hashlib, json, os, pathlib, sys, time, urllib.error, urllib.request
import yaml

root, slot, model, seed = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
cfg = yaml.safe_load((root / "site/art/prompts.yaml").read_text(encoding="utf-8"))
job, quality = {}, cfg.get("quality", "medium")
if slot.startswith("pack:"):
    pf = root / f"site/art/packs/{slot[5:]}.yaml"
    job = yaml.safe_load(pf.read_text(encoding="utf-8")) if pf.is_file() else sys.exit(f"art-gen: no {pf}")
    looks = " ".join(f"({i}) {s['look']}, accent color {cfg['slots'][f'{i:02d}']['color']};"
                     for i, s in enumerate(job["slots"], 1))
    prompt = f"{cfg['sheet']} Style: {job['style']} The twelve characters, in reading order: {looks}"
elif slot.startswith("scene:"):
    sc = yaml.safe_load((root / "site/art/scenes.yaml").read_text(encoding="utf-8"))
    job = sc["scenes"].get(slot[6:]) or sys.exit(f"art-gen: no scenes.{slot[6:]} in site/art/scenes.yaml")
    prompt = f"{sc['base'][job['kind']]} {job['prompt']}"
else:
    s = cfg["slots"].get(slot) or sys.exit(f"art-gen: no slot {slot!r} in prompts.yaml")
    prompt = f"{cfg['base']} The character: {s['look']}. Signature accent color {s['color']} on the outfit or eyes."
if model not in cfg["est"]:
    sys.exit(f"art-gen: no est price for {model} in prompts.yaml (add one before spending)")
size, budget = job.get("size", cfg["size"]), float(cfg["budget"])
est = 0.0 if model.endswith(":free") else float(job.get("est", cfg["est"][model]))
q = job.get("quality", quality)
key = hashlib.sha256(f"{model}{prompt}{size}{seed}{'' if q == quality else q}".encode()).hexdigest()[:24]
quality = q
raw = root / "site/art/raw"; raw.mkdir(parents=True, exist_ok=True)
out, ledger = raw / f"{key}.png", raw / "ledger.tsv"
if out.is_file():
    print(f"cache {slot} {model} seed={seed} -> {out.relative_to(root)}"); sys.exit(0)

total = 0.0
if ledger.is_file():
    for ln in ledger.read_text().splitlines()[1:]:
        total += float(ln.split("\t")[3])
if est > 0 and total + est >= budget:
    sys.exit(f"art-gen: HARD STOP — ledger ${total:.4f} + est ${est:.2f} ≥ budget ${budget:.2f}; ask the human")

body = {"model": model, "prompt": prompt, "size": size, "quality": "low" if model.endswith(":free") else quality,
        "background": "transparent", "output_format": "png", "response_format": "b64_json", "n": 1}
req = urllib.request.Request("https://api.imagerouter.io/v1/openai/images/generations",
                             data=json.dumps(body).encode(), method="POST",
                             headers={"Content-Type": "application/json",
                                      "Authorization": "Bearer " + os.environ["IMAGEROUTER_API_KEY"]})
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        res = json.load(r)
except urllib.error.HTTPError as e:
    sys.exit(f"art-gen: HTTP {e.code}: {e.read()[:400].decode(errors='replace')}")
d = (res.get("data") or [{}])[0]
if d.get("b64_json"):
    img = base64.b64decode(d["b64_json"])
elif d.get("url"):
    if not str(d["url"]).startswith("https://"):     # urlopen would also follow file:// or http://
        sys.exit(f"art-gen: refusing non-https image url: {str(d['url'])[:80]}")
    with urllib.request.urlopen(d["url"], timeout=120) as r:
        img = r.read()
else:
    sys.exit(f"art-gen: no image in response: {json.dumps(res)[:400]}")
cost = res.get("cost", (res.get("usage") or {}).get("cost"))
cost = est if cost is None else float(cost)   # unknown cost → book the worst-case estimate
out.write_bytes(img)
new = not ledger.is_file()
with ledger.open("a") as f:
    if new:
        f.write("ts\tmodel\tslot\tcost\tkey\n")
    f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')}\t{model}\t{slot}\t{cost:.4f}\t{key}\n")
print(f"gen {slot} {model} seed={seed} cost=${cost:.4f} total=${total + cost:.4f} -> {out.relative_to(root)}")
PY
