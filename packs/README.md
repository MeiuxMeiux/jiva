# packs — roster portraits

Each `packs/<name>/` is a roster: `pack.json` (slot → name, colour, avatar) plus `avatars/`.
`jiva roster [gen|check|show] [pack]` manages them; `default` is used unless you pick another.
`packs/local/` is gitignored and never committed: put private test rosters there.

## Where the portraits come from

- Every portrait is AI-generated (`openai/gpt-image-2` via ImageRouter, `scripts/art-gen.sh`)
  from the prompts committed in `site/art/prompts.yaml` (default pack and site scenes) and
  `site/art/packs/<name>.yaml` (one file per alternate pack). Post-processing is scripted
  (`site/art/artkey.py`); the chosen generations are recorded in `site/art/final/`.
- All characters are original. No pack depicts a real person, and no prompt names a franchise,
  studio or existing character. Style packs (for example `old-masters`, `ukiyo-e`) borrow a
  period look, not specific works.
- `fake-humans`: photoreal faces that are invented and AI-generated; they are not photos of,
  and are not meant to resemble, any real person.
- Names are short invented labels, cosmetic only: they never shape a session's behaviour.

## Licence

The portraits, `pack.json` files and prompts are part of this repository and are licensed under
its [MIT License](../LICENSE), like the code.

If you think an image resembles a real person or an existing work too closely, open an issue
or write to <jiva@meiuxmeiux.com> and it will be replaced.
