#!/usr/bin/env python3
"""serve site/build on 127.0.0.1:<port> for site-dev. stdlib http.server, except any request path
with a `..` segment is a 404 (http.server silently strips it and serves /, which would hide the
traversal check deploy-verify makes). Headers stay meta-only on purpose: the vhost adds the real ones."""
import functools, http.server, pathlib, sys, urllib.parse

OUT = pathlib.Path(__file__).resolve().parent.parent / "build"


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = urllib.parse.unquote(self.path.split("?")[0].split("#")[0])
        if ".." in path.replace("\\", "/").split("/"):
            self.send_error(404)
            return None
        return super().send_head()


if __name__ == "__main__":
    port = int(sys.argv[1])
    handler = functools.partial(Handler, directory=str(OUT))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)  # OSError if busy → caller retries
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
