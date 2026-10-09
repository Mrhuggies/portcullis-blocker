#!/usr/bin/env python3
"""Portcullis — local control panel.

A small server on 127.0.0.1 that serves the interface to your browser. The
only privileged step, writing the hosts file, goes through macOS's own
administrator prompt, and the root side refuses anything that isn't a block.

    python3 server.py
"""

import hashlib, http.server, json, os, pathlib, platform, re, secrets
import socketserver, subprocess, sys, tempfile, threading, time, urllib.parse

PORT = int(os.environ.get("PORTCULLIS_PORT", 7378))
HERE = pathlib.Path(__file__).resolve().parent          # .../app
ROOT = HERE.parent                                       # project or bundle Resources
IS_MAC = platform.system() == "Darwin"

STATE_DIR = pathlib.Path.home() / "Library/Application Support/Portcullis"
STATE = STATE_DIR / "user.json"
HOSTS = pathlib.Path("/etc/hosts")
GUARD_PLIST = pathlib.Path("/Library/LaunchDaemons/com.portcullis.guard.plist")
CHROME_POLICY = pathlib.Path("/Library/Managed Preferences/com.google.Chrome.plist")

BEGIN, END = "# >>> portcullis >>>", "# <<< portcullis <<<"
HOST_RE = re.compile(r"[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+")

# Generated once per launch. The page gets it; other websites can't read it,
# so they can't drive this server even though it's on your machine.
TOKEN = secrets.token_urlsafe(32)
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}

DEFAULTS = {"sites": [], "tools": {}, "pending": {}, "pendingTools": {},
            "waitHours": 48, "pendingWait": None, "released": []}


class Refused(Exception):
    """A request that's understood but not allowed — shown to the user."""


# ===================================================================== state
_corrupt = False


def catalogue():
    return json.loads((HERE / "tools.json").read_text())["tools"]


def load():
    """Read saved state. A damaged file is set aside, never silently replaced:
    starting from defaults would quietly drop someone's list on the next Apply."""
    global _corrupt
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    data = json.loads(json.dumps(DEFAULTS))
    if STATE.exists():
        try:
            saved = json.loads(STATE.read_text())
            if not isinstance(saved, dict):
                raise ValueError("not an object")
            data.update(saved)
            _corrupt = False
        except Exception:
            if not _corrupt:
                STATE.rename(STATE.with_suffix(f".damaged-{int(time.time())}.json"))
            _corrupt = True
    ids = {t["id"]: t["default"] for t in catalogue()}
    data["tools"] = {**ids, **{k: v for k, v in data["tools"].items() if k in ids}}
    return data


def save(data):
    """Write atomically, so a crash mid-save can't leave half a file."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".user.", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, STATE)


# ===================================================================== rules
def normalise(raw):
    s = str(raw or "").strip().lower()
    s = re.sub(r"^[a-z][a-z0-9+.-]*://", "", s)
    s = re.split(r"[/?#]", s)[0].split("@")[-1].split(":")[0]
    s = re.sub(r"^www\.", "", s).rstrip(".")
    if len(s) > 253 or not HOST_RE.fullmatch(s) or not re.search(r"\.[a-z]{2,}$", s):
        return None
    return s


def site_variants(host):
    return [host, f"www.{host}", f"m.{host}"]


def release(data, hosts):
    data["released"] = sorted(set(data["released"]) | set(hosts))


def tick(data):
    """Apply anything whose waiting period has finished. Returns True if changed.
    Finished removals are recorded as released: that list is the only thing
    Apply is ever allowed to take out of the hosts file."""
    now, changed = time.time(), False
    for host, when in list(data["pending"].items()):
        if now >= when:
            data["sites"] = [s for s in data["sites"] if s["host"] != host]
            del data["pending"][host]
            release(data, site_variants(host))
            changed = True
    by_id = {t["id"]: t for t in catalogue()}
    for tid, when in list(data["pendingTools"].items()):
        if now >= when:
            data["tools"][tid] = False
            del data["pendingTools"][tid]
            release(data, by_id.get(tid, {}).get("domains", []))
            changed = True
    pw = data.get("pendingWait")
    if pw and now >= pw["at"]:
        data["waitHours"], data["pendingWait"] = pw["hours"], None
        changed = True
    return changed


def wait_seconds(data):
    return data["waitHours"] * 3600


def act(data, req):
    """Every change the panel can make, with the rule that makes it safe:
    tightening is instant, loosening waits."""
    action = req.get("action")

    if action == "addSite":
        host = normalise(req.get("host"))
        if not host:
            raise Refused("That doesn't look like a website address.")
        if any(s["host"] == host for s in data["sites"]):
            raise Refused(f"{host} is already on your list.")
        data["sites"].append({"host": host, "added": time.time()})
        data["pending"].pop(host, None)
        return f"{host} added."

    if action in ("requestRemoval", "cancelRemoval"):
        host = normalise(req.get("host"))
        if not host or not any(s["host"] == host for s in data["sites"]):
            raise Refused("That site isn't on your list.")
        if action == "cancelRemoval":
            data["pending"].pop(host, None)
            return f"{host} stays blocked."
        data["pending"].setdefault(host, time.time() + wait_seconds(data))
        return f"{host} will come off after the waiting period."

    if action == "setTool":
        tid, on = req.get("id"), req.get("on")
        if tid not in data["tools"] or not isinstance(on, bool):
            raise Refused("Unknown setting.")
        if on:
            data["tools"][tid] = True
            data["pendingTools"].pop(tid, None)
            return "Blocked."
        if tid in data["pendingTools"]:
            del data["pendingTools"][tid]          # second click = keep it on
            return "Kept on."
        data["pendingTools"][tid] = time.time() + wait_seconds(data)
        return "Will switch off after the waiting period."

    if action == "setWait":
        try:
            hours = int(req.get("hours"))
        except (TypeError, ValueError):
            raise Refused("Give it a number of hours.")
        hours = max(1, min(720, hours))
        if hours >= data["waitHours"]:
            data["waitHours"], data["pendingWait"] = hours, None
            return f"Waiting period is now {hours} hours."
        data["pendingWait"] = {"hours": hours, "at": time.time() + wait_seconds(data)}
        return f"Will drop to {hours} hours once the current waiting period has passed."

    if action == "cancelWait":
        data["pendingWait"] = None
        return "Kept as it is."

    raise Refused("Unknown action.")


# =================================================================== payload
def desired_hosts(data):
    base = (ROOT / "blocklist.hosts").read_text().splitlines()
    hosts = [l.split()[1] for l in base if l.startswith("0.0.0.0 ") and len(l.split()) == 2]
    by_id = {t["id"]: t for t in catalogue()}
    for tid, on in data["tools"].items():
        if on and tid in by_id:
            hosts += by_id[tid]["domains"]
    for s in data["sites"]:
        hosts += site_variants(s["host"])
    seen, out = set(), []
    for h in hosts:
        if h not in seen and HOST_RE.fullmatch(h):
            seen.add(h)
            out.append(h)
    return out


def payload_hosts(data, installed=None):
    """What Apply writes: everything wanted, plus anything already blocked that
    hasn't been released. Without the second part, entries from an earlier
    setup — or blocks someone added by hand — would vanish with no wait at all."""
    want = desired_hosts(data)
    installed = installed_hosts() if installed is None else installed
    keep, released, seen = [], set(data["released"]), set(want)
    for h in installed or []:
        if h not in seen and h not in released and HOST_RE.fullmatch(h):
            keep.append(h)
            seen.add(h)
    return want + keep


def build_payload(data):
    hosts = payload_hosts(data)
    return "\n".join([BEGIN, f"# Generated by Portcullis — {len(hosts):,} hosts.",
                      *(f"0.0.0.0 {h}" for h in hosts), END, ""])


def installed_hosts():
    try:
        lines = HOSTS.read_text().splitlines()
    except OSError:
        return None
    inside, out = False, []
    for l in lines:
        if l == BEGIN:
            inside = True
        elif l == END:
            inside = False
        elif inside and l.startswith("0.0.0.0 "):
            out.append(l.split()[1])
    return out if BEGIN in lines else None


def status(data):
    current = installed_hosts()
    have = set(current or [])
    want = set(desired_hosts(data))
    target = set(payload_hosts(data, current))
    return {
        "installed": current is not None,
        "count": len(current or []),
        "upToDate": current is not None and target == have,
        "toAdd": len(target - have),
        "toRemove": len(have - target),
        "kept": len(target - want),
        "guard": GUARD_PLIST.exists(),
        "chromeProfile": CHROME_POLICY.exists(),
        "corrupt": _corrupt,
        "mac": IS_MAC,
        "os": "mac",
    }


def apply_block(data):
    if not IS_MAC:
        raise Refused("This copy of the panel is for Mac. Windows has its own: Portcullis.cmd.")
    if _corrupt:
        raise Refused("Your saved settings were damaged, so I won't apply them. "
                      "A copy is in ~/Library/Application Support/Portcullis.")

    payload = STATE_DIR / "payload.hosts"
    payload.write_text(build_payload(data))
    script = ROOT / "mac" / "apply-payload.sh"

    # Paths go in as arguments, never spliced into the script text, so an
    # unusual folder name can't change what runs as root.
    osa = ['osascript',
           '-e', 'on run argv',
           '-e', 'do shell script "/bin/bash " & quoted form of item 1 of argv & " " & '
                 'quoted form of item 2 of argv & " --with-guard " & quoted form of item 3 of argv '
                 'with prompt "Portcullis needs your password to update the block list." '
                 'with administrator privileges',
           '-e', 'end run',
           str(script), str(payload), str(ROOT / "mac")]
    r = subprocess.run(osa, capture_output=True, text=True)
    if r.returncode != 0:
        err = r.stderr.strip()
        if "-128" in err or "User canceled" in err:
            raise Refused("You cancelled the password prompt, so nothing changed.")
        last = err.splitlines()[-1] if err else "unknown error"
        raise Refused(f"Couldn't apply: {re.sub(r'^.*?execution error: ', '', last)}")
    return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "Done."


def open_profile():
    """Hands the Chrome profile to macOS and opens the page where it's approved.
    macOS never lets an app install a profile itself — a person has to click
    Install and enter their password — so this is as far as it can go."""
    if not IS_MAC:
        raise Refused("Only needed on a Mac.")
    profile = ROOT / "mac" / "Portcullis.mobileconfig"
    if not profile.is_file():
        raise Refused("The Chrome profile is missing from this copy of the app.")
    if os.environ.get("PORTCULLIS_DRY_OPEN"):           # tests: don't really open anything
        return "Opened (dry run)."
    subprocess.run(["open", str(profile)], check=False)
    time.sleep(1.5)
    subprocess.run(["open", "x-apple.systempreferences:com.apple.Profiles-Settings.extension"], check=False)
    return "Now finish in System Settings — the steps are below."


# ==================================================================== server
INDEX = None
IMG_RE = re.compile(r"/img/([a-z0-9-]+)\.(png|jpg)")
TYPES = {"png": "image/png", "jpg": "image/jpeg"}


def index_html():
    global INDEX
    if INDEX is None:
        INDEX = (HERE / "ui" / "index.html").read_text().replace("__PORTCULLIS_TOKEN__", TOKEN).encode()
    return INDEX


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "Portcullis"

    def log_message(self, *a):
        pass

    def _reply(self, code, body, ctype="application/json"):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", f"{ctype}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
                         "connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def _trusted(self, need_token):
        # Host check defeats DNS rebinding: a hostile site resolving to
        # 127.0.0.1 still sends its own name here.
        if self.headers.get("Host") not in ALLOWED_HOSTS:
            return False
        origin = self.headers.get("Origin")
        if origin and urllib.parse.urlparse(origin).netloc not in ALLOWED_HOSTS:
            return False
        # A custom header can't be sent cross-site without a CORS preflight,
        # which this server never approves.
        return not need_token or secrets.compare_digest(
            self.headers.get("X-Portcullis-Token", ""), TOKEN)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/hello":                       # used by the launcher
            return self._reply(200, {"app": "portcullis"}) if self._trusted(False) else self._reply(403, {})
        if not self._trusted(path.startswith("/api/")):
            return self._reply(403, {"error": "forbidden"})
        if path in ("/", "/index.html"):
            return self._reply(200, index_html(), "text/html")
        # The setup guide and its pictures. Names are matched by pattern and
        # looked up in one folder, so nothing else on disk can be reached.
        if path == "/guide.html":
            return self._reply(200, (HERE / "ui" / "guide.html").read_bytes(), "text/html")
        m = IMG_RE.fullmatch(path)
        if m and (HERE / "ui" / "img" / f"{m[1]}.{m[2]}").is_file():
            return self._reply(200, (HERE / "ui" / "img" / f"{m[1]}.{m[2]}").read_bytes(), TYPES[m[2]])
        if path == "/api/state":
            data = load()
            if tick(data) and not _corrupt:
                save(data)
            return self._reply(200, {"state": data, "status": status(data), "catalogue": catalogue()})
        self._reply(404, {"error": "not found"})

    def do_POST(self):
        if not self._trusted(True):
            return self._reply(403, {"error": "forbidden"})
        try:
            length = min(int(self.headers.get("Content-Length", 0)), 64 * 1024)
            req = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(req, dict):
                raise ValueError
        except (ValueError, json.JSONDecodeError):
            return self._reply(400, {"ok": False, "error": "Bad request."})

        if req.get("action") == "openProfile":
            try:
                msg = open_profile()
                return self._reply(200, {"ok": True, "message": msg})
            except Refused as e:
                return self._reply(200, {"ok": False, "error": str(e)})

        if req.get("action") == "quit":
            self._reply(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        data = load()
        tick(data)
        try:
            if req.get("action") == "apply":
                save(data)
                msg = apply_block(data)
                data["released"] = []
                save(data)
            else:
                if _corrupt:
                    raise Refused("Your saved settings were damaged — restart the panel to begin fresh.")
                msg = act(data, req)
                save(data)
            self._reply(200, {"ok": True, "message": msg, "state": data, "status": status(data)})
        except Refused as e:
            self._reply(200, {"ok": False, "error": str(e), "state": data, "status": status(data)})
        except Exception as e:                          # never take the panel down
            self._reply(500, {"ok": False, "error": f"Something went wrong: {e}"})


def main():
    socketserver.TCPServer.allow_reuse_address = True
    try:
        httpd = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        print(f"Port {PORT} is already in use by another program.", file=sys.stderr)
        sys.exit(3)
    with httpd:
        print(f"Portcullis panel on http://127.0.0.1:{PORT}/", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
