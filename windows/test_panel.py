"""Over-the-wire tests for the Windows panel (panel.ps1), the same checks
app/test_server.py makes of the Mac one. Needs PowerShell 7 ("pwsh") or
Windows PowerShell on the PATH, or PWSH=/path/to/pwsh.

    python3 -m unittest windows/test_panel.py -v
"""

import http.client, json, os, pathlib, shutil, socket, subprocess, tempfile, time, unittest

HERE = pathlib.Path(__file__).resolve().parent
PWSH = os.environ.get("PWSH") or shutil.which("pwsh") or shutil.which("powershell")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@unittest.skipUnless(PWSH, "PowerShell not found")
class Wire(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = tempfile.mkdtemp(prefix="portcullis-win-test-")
        hosts = pathlib.Path(cls.home) / "hosts"
        hosts.write_text("127.0.0.1 localhost\n# >>> portcullis >>>\n0.0.0.0 x.com\n# <<< portcullis <<<\n")
        cls.port = free_port()
        env = {**os.environ, "PORTCULLIS_PORT": str(cls.port), "PORTCULLIS_HOME": cls.home,
               "PORTCULLIS_HOSTS": str(hosts), "PORTCULLIS_NO_BROWSER": "1"}
        cls.proc = subprocess.Popen([PWSH, "-NoProfile", "-File", str(HERE / "panel.ps1")], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(150):
            try:
                if cls.req("GET", "/api/hello")[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.1)
        status, body = cls.req("GET", "/")
        cls.token = body.split('TOKEN = "')[1].split('"')[0] if 'TOKEN = "' in body else None

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)
        shutil.rmtree(cls.home, ignore_errors=True)

    @classmethod
    def req(cls, method, path, body=None, headers=None, host=None, raw=None):
        c = http.client.HTTPConnection("localhost", cls.port, timeout=10)
        h = {"Host": host or f"localhost:{cls.port}"}
        h.update(headers or {})
        data = raw if raw is not None else (json.dumps(body) if body is not None else None)
        c.request(method, path, body=data, headers=h)
        r = c.getresponse()
        out = r.read().decode()
        cls.last_headers = r
        c.close()
        return r.status, out

    def post(self, body, token=True, **kw):
        h = {"Content-Type": "application/json"}
        if token:
            h["X-Portcullis-Token"] = self.token
        h.update(kw.pop("headers", {}))
        return self.req("POST", "/api/action", body, headers=h, **kw)

    def state(self):
        return json.loads(self.req("GET", "/api/state", headers={"X-Portcullis-Token": self.token})[1])

    # ---------------------------------------------------------------- access
    def test_page_carries_a_token(self):
        self.assertTrue(self.token and len(self.token) > 30)

    def test_hello_needs_no_token(self):
        s, body = self.req("GET", "/api/hello")
        self.assertEqual((s, json.loads(body)["app"]), (200, "portcullis"))

    def test_state_needs_token(self):
        self.assertEqual(self.req("GET", "/api/state")[0], 403)
        self.assertEqual(self.req("GET", "/api/state", headers={"X-Portcullis-Token": "guess"})[0], 403)
        self.assertEqual(self.req("GET", "/api/state", headers={"X-Portcullis-Token": self.token})[0], 200)

    def test_post_without_or_with_wrong_token(self):
        self.assertEqual(self.post({"action": "addSite", "host": "example.org"}, token=False)[0], 403)
        self.assertEqual(self.req("POST", "/api/action", {"action": "quit"},
                                  headers={"X-Portcullis-Token": ("B" if self.token[0] == "A" else "A") + self.token[1:]})[0], 403)

    def test_dns_rebinding_host_is_refused(self):
        # Windows itself turns away a Host that doesn't match its prefix (400/404);
        # the panel's own check is the second line behind it.
        self.assertIn(self.req("GET", "/", host=f"evil.example:{self.port}")[0], (400, 403, 404))

    def test_foreign_origin_is_refused(self):
        s, _ = self.post({"action": "addSite", "host": "example.org"}, headers={"Origin": "https://evil.example"})
        self.assertEqual(s, 403)
        s, _ = self.post({"action": "addSite", "host": "example.org"}, headers={"Origin": "null"})
        self.assertEqual(s, 403)

    def test_path_traversal(self):
        for p in ("/../panel.ps1", "/..%2fpanel.ps1", "/tools.json", "/ui/index.html", "/app/tools.json"):
            self.assertIn(self.req("GET", p)[0], (400, 404), p)

    def test_other_methods(self):
        self.assertEqual(self.req("PUT", "/api/action", {})[0], 405)

    def test_malformed_json(self):
        h = {"X-Portcullis-Token": self.token}
        self.assertEqual(self.req("POST", "/api/action", headers=h, raw="{nope")[0], 400)
        self.assertEqual(self.req("POST", "/api/action", headers=h, raw="[1,2]")[0], 400)

    def test_guide_and_pictures(self):
        s, body = self.req("GET", "/guide.html")
        self.assertEqual(s, 200)
        self.assertNotIn(self.token, body)
        c = http.client.HTTPConnection("localhost", self.port, timeout=10)
        c.request("GET", "/img/win-uac.png", headers={"Host": f"localhost:{self.port}"})
        r = c.getresponse(); data = r.read(); c.close()
        self.assertEqual((r.status, r.getheader("Content-Type").split(";")[0]), (200, "image/png"))
        self.assertTrue(data.startswith(b"\x89PNG"))

    def test_pictures_cannot_reach_other_files(self):
        for p in ("/img/../panel.ps1", "/img/..%2fpanel.ps1", "/img/missing.png", "/img/x.svg",
                  "/img/Win-UAC.png", "/img/a/b.png", "/ui/guide.html"):
            self.assertIn(self.req("GET", p)[0], (400, 404), p)

    def test_open_profile_is_mac_only(self):
        d = json.loads(self.post({"action": "openProfile"})[1])
        self.assertFalse(d["ok"])
        self.assertIn("Windows", d["error"])

    def test_security_headers(self):
        self.req("GET", "/")
        r = self.last_headers
        self.assertIn("frame-ancestors 'none'", r.getheader("Content-Security-Policy"))
        self.assertEqual(r.getheader("Cache-Control"), "no-store")

    # ------------------------------------------------------------- behaviour
    def test_round_trip(self):
        s, body = self.post({"action": "addSite", "host": "https://www.example.net/"})
        d = json.loads(body)
        self.assertTrue(d["ok"], body)
        self.assertIn("example.net", [x["host"] for x in d["state"]["sites"]])
        self.assertEqual(d["status"]["os"], "windows")
        self.assertIn("example.net", [x["host"] for x in self.state()["state"]["sites"]])

    def test_refusal_is_friendly_not_a_crash(self):
        s, body = self.post({"action": "setWait", "hours": "lots"})
        d = json.loads(body)
        self.assertEqual(s, 200)
        self.assertFalse(d["ok"])
        self.assertIn("number", d["error"])

    def test_hand_added_block_is_counted_as_kept(self):
        st = self.state()["status"]
        self.assertTrue(st["installed"])
        self.assertGreaterEqual(st["kept"], 1, st)

    def test_state_shape_matches_the_mac_panel(self):
        d = self.state()
        self.assertEqual(set(d), {"state", "status", "catalogue"})
        self.assertTrue({"sites", "tools", "pending", "pendingTools", "waitHours", "pendingWait",
                         "released"} <= set(d["state"]))
        self.assertIsInstance(d["state"]["sites"], list)
        self.assertIsInstance(d["state"]["released"], list)
        self.assertIsInstance(d["catalogue"], list)
        self.assertTrue({"installed", "count", "upToDate", "toAdd", "toRemove", "kept", "guard",
                         "chromeProfile", "corrupt"} <= set(d["status"]))

    def test_tool_off_waits_over_the_wire(self):
        d = json.loads(self.post({"action": "setTool", "id": "nordvpn", "on": True})[1])
        self.assertTrue(d["state"]["tools"]["nordvpn"])
        d = json.loads(self.post({"action": "setTool", "id": "nordvpn", "on": False})[1])
        self.assertTrue(d["state"]["tools"]["nordvpn"])
        self.assertIn("nordvpn", d["state"]["pendingTools"])

    def test_apply_off_windows_is_refused_cleanly(self):
        if os.name == "nt":
            self.skipTest("would raise a real UAC prompt")
        d = json.loads(self.post({"action": "apply"})[1])
        self.assertFalse(d["ok"])
        self.assertIn("Windows", d["error"])

    def test_zz_quit(self):
        self.assertEqual(self.post({"action": "quit"})[0], 200)
        self.proc.wait(10)
        self.assertIsNotNone(self.proc.returncode, "panel kept running after quit")


if __name__ == "__main__":
    unittest.main(verbosity=2)
