"""Tests for the panel server. Nothing here touches the real system: state goes
to a throwaway home folder and the server runs on a spare port.

    python3 -m unittest app/test_server.py -v
"""

import http.client, json, os, pathlib, socket, subprocess, sys, tempfile, time, unittest

HERE = pathlib.Path(__file__).resolve().parent
TMP_HOME = tempfile.mkdtemp(prefix="portcullis-test-home-")
os.environ["HOME"] = TMP_HOME
sys.path.insert(0, str(HERE))
import server  # noqa: E402  (imported after HOME is redirected)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ============================================================ the rules alone
class Rules(unittest.TestCase):
    def setUp(self):
        self.d = server.load()
        self.d["sites"], self.d["pending"], self.d["pendingTools"] = [], {}, {}
        self.d["waitHours"], self.d["pendingWait"] = 48, None
        self.d["released"] = []

    def test_normalise(self):
        cases = {
            "https://www.Example.com/a?b#c": "example.com",
            "user@example.co.uk:8080/x": "example.co.uk",
            "  sub.example.com.  ": "sub.example.com",
            "not a site": None, "localhost": None, "192.168.1.1": None,
            "": None, None: None, "exa mple.com": None, "-bad.com": None,
            "x" * 300 + ".com": None,
        }
        for raw, want in cases.items():
            self.assertEqual(server.normalise(raw), want, raw)

    def test_adding_is_instant(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        self.assertEqual([s["host"] for s in self.d["sites"]], ["example.com"])
        self.assertIn("example.com", server.desired_hosts(self.d))
        self.assertIn("www.example.com", server.desired_hosts(self.d))

    def test_duplicates_refused(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        with self.assertRaises(server.Refused):
            server.act(self.d, {"action": "addSite", "host": "https://www.example.com/"})

    def test_removal_waits(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        server.act(self.d, {"action": "requestRemoval", "host": "example.com"})
        server.tick(self.d)
        self.assertEqual(len(self.d["sites"]), 1, "removed before the wait")
        self.d["pending"]["example.com"] = time.time() - 1          # wait served
        server.tick(self.d)
        self.assertEqual(self.d["sites"], [])

    def test_asking_twice_does_not_reset_the_clock(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        server.act(self.d, {"action": "requestRemoval", "host": "example.com"})
        first = self.d["pending"]["example.com"]
        time.sleep(0.01)
        server.act(self.d, {"action": "requestRemoval", "host": "example.com"})
        self.assertEqual(self.d["pending"]["example.com"], first)

    def test_cancel_keeps_it(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        server.act(self.d, {"action": "requestRemoval", "host": "example.com"})
        server.act(self.d, {"action": "cancelRemoval", "host": "example.com"})
        self.assertEqual(self.d["pending"], {})

    def test_tool_on_is_instant_off_waits(self):
        server.act(self.d, {"action": "setTool", "id": "nordvpn", "on": True})
        self.assertTrue(self.d["tools"]["nordvpn"])
        server.act(self.d, {"action": "setTool", "id": "nordvpn", "on": False})
        self.assertTrue(self.d["tools"]["nordvpn"], "switched off instantly")
        self.assertIn("nordvpn", self.d["pendingTools"])
        self.d["pendingTools"]["nordvpn"] = time.time() - 1
        server.tick(self.d)
        self.assertFalse(self.d["tools"]["nordvpn"])

    def test_unknown_tool_refused(self):
        for bad in ({"id": "nope", "on": True}, {"id": "tor", "on": "yes"}, {}):
            with self.assertRaises(server.Refused):
                server.act(self.d, {"action": "setTool", **bad})

    def test_wait_raise_instant_lower_delayed(self):
        server.act(self.d, {"action": "setWait", "hours": 72})
        self.assertEqual(self.d["waitHours"], 72)
        server.act(self.d, {"action": "setWait", "hours": 1})
        self.assertEqual(self.d["waitHours"], 72, "lowered instantly")
        self.assertEqual(self.d["pendingWait"]["hours"], 1)

    def test_bad_wait_input(self):
        for bad in ("abc", None, [], {}):
            with self.assertRaises(server.Refused):
                server.act(self.d, {"action": "setWait", "hours": bad})

    def test_payload_shape(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        p = server.build_payload(self.d).splitlines()
        self.assertEqual(p[0], server.BEGIN)
        self.assertEqual(p[-1], server.END)
        body = [l for l in p[1:-1] if not l.startswith("# ")]
        self.assertTrue(all(l.startswith("0.0.0.0 ") and len(l.split()) == 2 for l in body))
        hosts = [l.split()[1] for l in body]
        self.assertEqual(len(hosts), len(set(hosts)), "duplicates in payload")

    def test_payload_passes_the_root_validator(self):
        """The thing that runs as root must accept what the panel produces."""
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        f = pathlib.Path(TMP_HOME) / "check.hosts"
        f.write_text(server.build_payload(self.d))
        r = subprocess.run(["bash", str(HERE.parent / "mac" / "apply-payload.sh"), str(f), "--check"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


# ============================== Apply may only remove what served the wait
class OnlyReleasedComesOff(unittest.TestCase):
    def setUp(self):
        self.d = server.load()
        self.d.update(sites=[], pending={}, pendingTools={}, released=[], waitHours=48)

    def test_existing_blocks_are_kept(self):
        """Blocks from an earlier setup, or added by hand, must survive Apply."""
        installed = ["x.com", "www.x.com", "my-own-block.example"]
        out = server.payload_hosts(self.d, installed)
        for h in installed:
            self.assertIn(h, out, f"{h} would have been unblocked with no wait")

    def test_a_finished_removal_does_come_off(self):
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        installed = server.payload_hosts(self.d, [])          # as if applied
        server.act(self.d, {"action": "requestRemoval", "host": "example.com"})
        self.assertIn("example.com", server.payload_hosts(self.d, installed), "removed before the wait")
        self.d["pending"]["example.com"] = time.time() - 1
        server.tick(self.d)
        out = server.payload_hosts(self.d, installed)
        for h in ("example.com", "www.example.com", "m.example.com"):
            self.assertNotIn(h, out)

    def test_a_tool_switched_off_after_the_wait_comes_off(self):
        server.act(self.d, {"action": "setTool", "id": "nordvpn", "on": True})
        installed = server.payload_hosts(self.d, [])
        server.act(self.d, {"action": "setTool", "id": "nordvpn", "on": False})
        self.assertIn("nordvpn.com", server.payload_hosts(self.d, installed))
        self.d["pendingTools"]["nordvpn"] = time.time() - 1
        server.tick(self.d)
        self.assertNotIn("nordvpn.com", server.payload_hosts(self.d, installed))

    def test_readding_a_released_site_blocks_it_again(self):
        server.release(self.d, server.site_variants("example.com"))
        server.act(self.d, {"action": "addSite", "host": "example.com"})
        self.assertIn("example.com", server.payload_hosts(self.d, []))

    def test_nothing_unknown_is_ever_unblocked(self):
        """The property itself: without a release, Apply never shrinks the block."""
        installed = server.payload_hosts(self.d, ["kept-a.example", "kept-b.example"])
        for _ in range(3):
            installed = server.payload_hosts(self.d, installed)
        self.assertTrue({"kept-a.example", "kept-b.example"} <= set(installed))


# ==================================================== saved state on disk
class State(unittest.TestCase):
    def test_damaged_file_is_set_aside_not_overwritten(self):
        server.STATE.parent.mkdir(parents=True, exist_ok=True)
        server.STATE.write_text("{ this is not json")
        server._corrupt = False
        server.load()
        self.assertTrue(server._corrupt)
        kept = list(server.STATE.parent.glob("user.damaged-*.json"))
        self.assertTrue(kept, "damaged file was thrown away")
        with self.assertRaises(server.Refused):
            server.apply_block(server.load())
        for k in kept:
            k.unlink()
        server._corrupt = False

    def test_save_is_atomic(self):
        d = server.load()
        server.save(d)
        leftovers = list(server.STATE.parent.glob(".user.*.json"))
        self.assertEqual(leftovers, [], "temp file left behind")
        self.assertEqual(json.loads(server.STATE.read_text())["waitHours"], d["waitHours"])


# =========================================================== over the wire
class Wire(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        env = {**os.environ, "HOME": TMP_HOME, "PORTCULLIS_PORT": str(cls.port), "PORTCULLIS_DRY_OPEN": "1"}
        cls.proc = subprocess.Popen([sys.executable, str(HERE / "server.py")], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", cls.port), 0.1).close()
                break
            except OSError:
                time.sleep(0.1)
        status, body = cls.req("GET", "/")
        cls.token = body.split('TOKEN = "')[1].split('"')[0] if 'TOKEN = "' in body else None

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)

    @classmethod
    def req(cls, method, path, body=None, headers=None, host=None):
        c = http.client.HTTPConnection("127.0.0.1", cls.port, timeout=5)
        h = {"Host": host or f"127.0.0.1:{cls.port}"}
        h.update(headers or {})
        c.request(method, path, body=json.dumps(body) if body is not None else None, headers=h)
        r = c.getresponse()
        data = r.read().decode()
        c.close()
        return r.status, data

    def post(self, body, token=True, **kw):
        h = {"Content-Type": "application/json"}
        if token:
            h["X-Portcullis-Token"] = self.token
        h.update(kw.pop("headers", {}))
        return self.req("POST", "/api/action", body, headers=h, **kw)

    def test_page_carries_a_token(self):
        self.assertTrue(self.token and len(self.token) > 30)

    def test_state_needs_token(self):
        self.assertEqual(self.req("GET", "/api/state")[0], 403)
        ok = self.req("GET", "/api/state", headers={"X-Portcullis-Token": self.token})
        self.assertEqual(ok[0], 200)

    def test_post_without_token_is_refused(self):
        self.assertEqual(self.post({"action": "addSite", "host": "example.org"}, token=False)[0], 403)

    def test_wrong_token_is_refused(self):
        s, _ = self.req("POST", "/api/action", {"action": "quit"},
                        headers={"X-Portcullis-Token": "guess"})
        self.assertEqual(s, 403)

    def test_dns_rebinding_host_is_refused(self):
        self.assertEqual(self.req("GET", "/", host="evil.example:%d" % self.port)[0], 403)

    def test_foreign_origin_is_refused(self):
        s, _ = self.post({"action": "addSite", "host": "example.org"},
                         headers={"Origin": "https://evil.example"})
        self.assertEqual(s, 403)

    def test_path_traversal(self):
        for p in ("/../server.py", "/..%2fserver.py", "/tools.json", "/etc/passwd", "/ui/../server.py"):
            self.assertEqual(self.req("GET", p)[0], 404, p)

    def test_malformed_json(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("POST", "/api/action", body="{nope",
                  headers={"Host": f"127.0.0.1:{self.port}", "X-Portcullis-Token": self.token})
        self.assertEqual(c.getresponse().status, 400)
        c.close()

    def test_round_trip(self):
        s, body = self.post({"action": "addSite", "host": "https://www.example.net/"})
        d = json.loads(body)
        self.assertTrue(d["ok"])
        self.assertIn("example.net", [x["host"] for x in d["state"]["sites"]])
        self.assertIn("upToDate", d["status"])

    def test_refusal_is_friendly_not_a_crash(self):
        s, body = self.post({"action": "setWait", "hours": "lots"})
        d = json.loads(body)
        self.assertEqual(s, 200)
        self.assertFalse(d["ok"])
        self.assertIn("number", d["error"])

    def test_hello_needs_no_token(self):
        s, body = self.req("GET", "/api/hello")
        self.assertEqual((s, json.loads(body)["app"]), (200, "portcullis"))

    def test_guide_and_pictures(self):
        s, body = self.req("GET", "/guide.html")
        self.assertEqual(s, 200)
        self.assertNotIn(self.token, body, "the guide must not carry the token")
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/img/mac-profile-pending.png", headers={"Host": f"127.0.0.1:{self.port}"})
        r = c.getresponse(); data = r.read(); c.close()
        self.assertEqual((r.status, r.getheader("Content-Type").split(";")[0]), (200, "image/png"))
        self.assertTrue(data.startswith(b"\x89PNG"))

    def test_pictures_cannot_reach_other_files(self):
        for p in ("/img/../server.py", "/img/..%2fserver.py", "/img/missing.png", "/img/x.svg",
                  "/img/Mac-Profile.png", "/img/a/b.png", "/ui/guide.html"):
            self.assertEqual(self.req("GET", p)[0], 404, p)
        self.assertEqual(self.req("GET", "/guide.html", host="evil.example")[0], 403)

    def test_open_profile_needs_token(self):
        self.assertEqual(self.post({"action": "openProfile"}, token=False)[0], 403)
        d = json.loads(self.post({"action": "openProfile"})[1])
        self.assertTrue(d["ok"], d)

    def test_security_headers(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/", headers={"Host": f"127.0.0.1:{self.port}"})
        r = c.getresponse(); r.read(); c.close()
        self.assertIn("frame-ancestors 'none'", r.getheader("Content-Security-Policy"))
        self.assertEqual(r.getheader("Cache-Control"), "no-store")


if __name__ == "__main__":
    unittest.main(verbosity=2)
