#!/usr/bin/env python3
"""Builds the walkthrough images in app/ui/img from guide/raw.

Two kinds of picture:
  - real screenshots (guide/raw), with numbered red call-outs added and any
    personal details covered;
  - drawn illustrations of screens that can't be captured from a Mac — Windows,
    phones, and prompts that only appear on a fresh machine. The guide labels
    these "Illustration" so nobody mistakes them for the real thing.

    python3 guide/make-images.py           (needs Google Chrome)
"""

import pathlib, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE.parent / "app" / "ui" / "img"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

BASE = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{overflow:hidden}
body{font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased;position:relative}
.hl{position:absolute;border:3px solid #e5484d;border-radius:10px;box-shadow:0 0 0 2px rgba(255,255,255,.85)}
.hl b{position:absolute;top:-15px;left:-15px;width:26px;height:26px;border-radius:50%;background:#e5484d;color:#fff;
      font:700 13px/22px -apple-system,system-ui,sans-serif;text-align:center;border:2px solid #fff}
.clip{position:absolute;overflow:hidden}
.clip img{position:absolute}
"""


def hl(n, x, y, w, h, r=10):
    return f'<div class="hl" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;border-radius:{r}px"><b>{n}</b></div>'


def raw(name):
    return (RAW / name).as_uri()


# ------------------------------------------------------------------ the images
IMAGES = {}


def image(name, w, h, css=""):
    def wrap(fn):
        IMAGES[name] = (w, h, css, fn)
        return fn
    return wrap


# ---- Mac: first launch -------------------------------------------------------
@image("mac-not-opened", 320, 300, "body{background:#dfe1e6}")
def _():
    # Real capture. The alert is cut out of its background along its own edge.
    return f"""
<div class="clip" style="left:30px;top:26px;width:259px;height:247px;border-radius:24px;
     box-shadow:0 18px 50px rgba(0,0,0,.25)">
  <img src="{raw('mac-not-opened.png')}" style="left:-5px;top:-2.5px;width:278px"></div>
{hl(1, 45, 228, 117, 37)}"""


@image("mac-open-anyway", 512, 222, "body{background:#ececec}")
def _():
    return f"""
<div class="clip" style="left:16px;top:16px;width:480px;height:190px;border-radius:12px">
  <img src="{raw('mac-open-anyway.png')}" style="left:0;top:0;width:480px"></div>
{hl(1, 365, 106, 118, 36)}"""


@image("mac-password", 316, 384, "body{background:#dfe1e6}")
def _():
    # Real capture; the username is replaced so nobody's name ships in the guide.
    return f"""
<div class="clip" style="left:31px;top:26px;width:254px;height:332px;border-radius:24px;
     box-shadow:0 18px 50px rgba(0,0,0,.25)">
  <img src="{raw('mac-password.png')}" style="left:-8px;top:-2.5px;width:270px">
  <div style="position:absolute;left:11px;top:217px;width:229px;height:24px;background:#e5e5e5;border-radius:6px;
       font-size:12.5px;line-height:24px;padding-left:7px;color:#222">Your name</div>
  <div style="position:absolute;left:0;top:0;width:254px;height:22px;background:#f8f8f9"></div>
  <div style="position:absolute;left:84px;top:0;width:170px;height:84px;background:#f8f8f9"></div>
  <div style="position:absolute;left:0;top:0;width:22px;height:84px;background:#f8f8f9"></div></div>
{hl(1, 33, 268, 248, 34)}
{hl(2, 155, 309, 124, 38)}"""


@image("mac-clt", 330, 330, "body{background:#dfe1e6}")
def _():
    return f"""
<div style="position:absolute;left:35px;top:24px;width:260px;padding:20px 18px 16px;background:#f6f6f8;border-radius:24px;
     box-shadow:0 18px 50px rgba(0,0,0,.25);font-size:12px;color:#222">
  <div style="width:52px;height:52px;border-radius:12px;background:linear-gradient(#8d939c,#5d636b);color:#fff;
       font-size:28px;line-height:52px;text-align:center;margin-bottom:12px">⚒</div>
  <div style="font-weight:700;font-size:12.5px;line-height:1.35;margin-bottom:8px">The “python3” command requires the command
    line developer tools. Would you like to install the tools now?</div>
  <div style="font-size:11.5px;line-height:1.4;color:#444;margin-bottom:14px">Choose Install to download and install the
    command line developer tools now.</div>
  <div style="display:grid;gap:7px">
    <div data-hl="1" data-r="999" style="background:#2f7cf6;color:#fff;border-radius:999px;text-align:center;padding:6px">Install</div>
    <div style="background:#e3e3e6;border-radius:999px;text-align:center;padding:6px">Not Now</div>
    <div style="background:#e3e3e6;border-radius:999px;text-align:center;padding:6px">Get Xcode</div>
  </div></div>"""


# ---- Mac: Chrome profile -----------------------------------------------------
@image("chrome-policy", 800, 434)
def _():
    # Real capture. The blocklist value is blurred — it listed one person's own sites.
    return f"""
<img src="{raw('chrome-policy.png')}" style="position:absolute;left:0;top:0;width:800px">
<div style="position:absolute;left:218px;top:400px;width:212px;height:26px;backdrop-filter:blur(5px);
     background:rgba(255,255,255,.35);border-radius:4px"></div>"""


@image("mac-terminal-remove", 900, 280, "body{background:#dfe1e6}")
def _():
    return """
<div style="position:absolute;left:20px;top:20px;width:860px;height:240px;border-radius:12px;overflow:hidden;
     box-shadow:0 14px 40px rgba(0,0,0,.25);background:#1e1e1e">
  <div style="height:30px;background:#2c2c2e;display:flex;align-items:center;gap:7px;padding-left:12px">
    <i style="width:12px;height:12px;border-radius:50%;background:#ff5f57"></i>
    <i style="width:12px;height:12px;border-radius:50%;background:#febc2e"></i>
    <i style="width:12px;height:12px;border-radius:50%;background:#28c840"></i>
    <span style="flex:1;text-align:center;color:#aaa;font-size:12px;margin-right:60px">Terminal</span></div>
  <pre style="color:#e6e6e6;font:12px/1.6 ui-monospace,Menlo,monospace;padding:12px 14px;white-space:pre">you@Mac ~ % <span data-hl="1" data-badge="above" data-pad="3" data-r="6" style="color:#fff">sudo bash /Applications/Portcullis.app/Contents/Resources/mac/uninstall-hosts.sh</span>
Password:

Removal requested. Nothing has been removed yet.
  Come back after Sun 11 Oct, 15:02 and run this again to confirm.
  Changed your mind: sudo bash /Applications/Portcullis.app/Contents/Resources/mac/uninstall-hosts.sh --cancel
you@Mac ~ % </pre></div>"""


# ---- Windows -------------------------------------------------------------------
WIN = "font-family:'Segoe UI',system-ui,sans-serif;"


@image("win-extract", 520, 340, "body{background:#e8eef4}")
def _():
    return f"""
<div style="position:absolute;left:20px;top:20px;width:480px;height:300px;background:#fff;border:1px solid #cfd6de;
     border-radius:8px;box-shadow:0 12px 32px rgba(0,0,0,.18);{WIN}font-size:12.5px;color:#1b1b1b">
  <div style="height:32px;display:flex;align-items:center;padding:0 12px;font-size:12px;color:#444;border-bottom:1px solid #eee">
    Extract Compressed (Zipped) Folders</div>
  <div style="padding:16px 22px">
    <div style="font-size:15px;color:#1a4fa0;margin-bottom:14px">Select a Destination and Extract Files</div>
    <div style="margin-bottom:6px">Files will be extracted to this folder:</div>
    <div style="display:flex;gap:8px;margin-bottom:12px">
      <div data-hl="1" data-r="6" style="flex:1;border:1px solid #9aa4ae;border-radius:3px;padding:5px 7px">C:\\Users\\you\\Documents\\Portcullis-Windows</div>
      <div style="border:1px solid #c5ccd3;border-radius:4px;padding:5px 12px;background:#f5f6f7">Browse...</div></div>
    <div>☑ Show extracted files when complete</div></div>
  <div style="position:absolute;right:16px;bottom:14px;display:flex;gap:8px">
    <div data-hl="2" data-r="6" style="background:#0067c0;color:#fff;border-radius:4px;padding:6px 22px">Extract</div>
    <div style="border:1px solid #c5ccd3;border-radius:4px;padding:6px 18px">Cancel</div></div></div>
"""


def smartscreen(expanded):
    extra = """<div style="margin:14px 0 0;line-height:1.7">App: <b style="font-weight:600">Portcullis.cmd</b><br>
      Publisher: <b style="font-weight:600">Unknown publisher</b></div>""" if expanded else \
        """<div style="margin-top:12px"><span data-hl="1" data-r="6" style="text-decoration:underline">More info</span></div>"""
    buttons = """<div data-hl="1" data-r="6" style="border:1px solid #fff;padding:7px 18px">Run anyway</div>
                 <div style="background:#fff;color:#0d5ca8;padding:8px 18px">Don't run</div>""" if expanded else \
        """<div style="background:#fff;color:#0d5ca8;padding:8px 18px">Don't run</div>"""
    return f"""
<div style="position:absolute;inset:0;background:#0d5ca8;color:#fff;{WIN}padding:34px 36px;font-size:13.5px">
  <div style="font-size:27px;font-weight:300;margin-bottom:18px">Windows protected your PC</div>
  <div style="line-height:1.55;max-width:470px">Microsoft Defender SmartScreen prevented an unrecognized app from
    starting. Running this app might put your PC at risk.</div>{extra}
  <div style="position:absolute;right:28px;bottom:26px;display:flex;gap:10px">{buttons}</div></div>"""


@image("win-smartscreen-1", 560, 300)
def _():
    return smartscreen(False)


@image("win-smartscreen-2", 560, 300)
def _():
    return smartscreen(True)


@image("win-uac", 480, 330, "body{background:#1f3550}")
def _():
    return f"""
<div style="position:absolute;left:30px;top:22px;width:420px;border-radius:8px;overflow:hidden;
     box-shadow:0 14px 40px rgba(0,0,0,.4);{WIN}">
  <div style="background:#2b2b2b;color:#fff;padding:14px 20px 16px">
    <div style="font-size:12px;color:#ccc;margin-bottom:10px">User Account Control</div>
    <div style="font-size:18px;line-height:1.3">Do you want to allow this app to make changes to your device?</div></div>
  <div style="background:#202020;color:#eee;padding:14px 20px 18px;font-size:12.5px">
    <div style="display:flex;gap:12px;align-items:center;margin-bottom:12px">
      <div style="width:34px;height:34px;border-radius:6px;background:#2a5fa8;color:#fff;font:700 15px/34px Menlo,monospace;
           text-align:center">&gt;_</div>
      <div style="font-size:15px">Windows PowerShell</div></div>
    <div style="color:#bbb;line-height:1.6">Verified publisher: Microsoft Windows<br>
      <span style="color:#6cb4ff">Show more details</span></div>
    <div style="display:flex;gap:10px;margin-top:16px">
      <div data-hl="1" data-r="6" style="flex:1;background:#4cc2ff;color:#000;border-radius:4px;text-align:center;padding:7px">Yes</div>
      <div style="flex:1;background:#3a3a3a;border-radius:4px;text-align:center;padding:7px">No</div></div></div></div>
"""


@image("win-powershell-remove", 900, 230, "body{background:#e8eef4}")
def _():
    return f"""
<div style="position:absolute;left:20px;top:20px;width:860px;height:190px;border-radius:8px;overflow:hidden;
     box-shadow:0 12px 32px rgba(0,0,0,.25);background:#0c0c0c">
  <div style="height:30px;background:#1f1f1f;color:#ddd;font:12px/30px 'Segoe UI',system-ui;padding-left:12px">
    Administrator: Windows PowerShell</div>
  <pre style="color:#ccc;font:12px/1.6 Consolas,ui-monospace,Menlo,monospace;padding:12px 14px;white-space:pre">PS C:\\Windows\\system32&gt; <span data-hl="1" data-badge="above" data-pad="3" data-r="6" style="color:#fff">cd $HOME\\Documents\\Portcullis-Windows</span>
PS C:\\Users\\you\\Documents\\Portcullis-Windows&gt; <span data-hl="2" data-badge="above" data-pad="3" data-r="6" style="color:#fff">powershell -ExecutionPolicy Bypass -File .\\app\\windows\\uninstall.ps1</span>

<span style="color:#f9f1a5">Removal requested. Nothing has been removed yet.</span>
  Come back after Sun 11 Oct, 15:02 and run this again to confirm.</pre></div>
"""


# ---- Android -------------------------------------------------------------------
PHONE = ("position:absolute;left:20px;top:20px;width:320px;height:600px;border-radius:34px;overflow:hidden;"
         "border:8px solid #111;background:{bg};box-shadow:0 14px 40px rgba(0,0,0,.25);"
         "font-family:Roboto,system-ui,sans-serif")


def android_settings(dim=False):
    rows = [("Internet", "HomeWiFi"), ("Calls & SMS", ""), ("SIMs", ""), ("Airplane mode", ""),
            ("Hotspot & tethering", "Off"), ("Data Saver", "Off"), ("VPN", "None"), ("Private DNS", "Automatic")]
    items = "".join(f"""<div {'data-hl="1" data-pad="0" data-r="14"' if t == "Private DNS" and not dim else ""} style="padding:13px 22px"><div style="font-size:15px;color:#1b1c1f">{t}</div>
        {f'<div style="font-size:12.5px;color:#5f6368;margin-top:2px">{s}</div>' if s else ''}</div>""" for t, s in rows)
    shade = '<div style="position:absolute;inset:0;background:rgba(0,0,0,.45)"></div>' if dim else ""
    return f"""<div style="{PHONE.format(bg='#f6f8fc')}">
  <div style="height:26px;font-size:11px;color:#333;padding:7px 22px">9:41</div>
  <div style="padding:14px 18px 18px;font-size:24px;color:#1b1c1f">← &nbsp;Network &amp; internet</div>{items}{shade}"""


@image("android-network", 360, 640, "body{background:#e9edf2}")
def _():
    return android_settings() + "</div>"


@image("android-private-dns", 360, 640, "body{background:#e9edf2}")
def _():
    radio = lambda on: (f'<span style="display:inline-block;width:18px;height:18px;border-radius:50%;border:2px solid '
                        f'{"#0b57d0" if on else "#5f6368"};vertical-align:middle;margin-right:14px;'
                        f'box-shadow:inset 0 0 0 3px #eef1f8{",inset 0 0 0 9px #0b57d0" if on else ""}"></span>')
    return android_settings(dim=True) + f"""
  <div style="position:absolute;left:18px;right:18px;top:150px;background:#eef1f8;border-radius:26px;padding:22px 22px 18px;
       color:#1b1c1f">
    <div style="font-size:20px;margin-bottom:16px">Select Private DNS mode</div>
    <div style="font-size:14.5px;line-height:2.4">{radio(False)}Off<br>{radio(False)}Automatic<br>
      <span data-hl="1" data-pad="4" style="white-space:nowrap;font-size:13.5px">{radio(True)}Private DNS provider hostname</span></div>
    <div data-hl="2" style="border:2px solid #0b57d0;border-radius:6px;padding:9px 10px;font-size:14px;margin:6px 0 18px">
      your-id.dns.nextdns.io</div>
    <div style="text-align:right;font-size:14px;color:#0b57d0;font-weight:500">Cancel &nbsp;&nbsp;&nbsp; <span data-hl="3" data-r="8">Save</span></div></div>
</div>"""


# ---- iPhone --------------------------------------------------------------------
IOS = "font-family:-apple-system,system-ui,sans-serif;"


def ios_alert(title, body, buttons, mark=""):
    btns = "".join(f'<div {mark if b[1] else ""} style="flex:1;text-align:center;padding:11px;color:#0a84ff;{"font-weight:600;" if b[1] else ""}'
                   f'{"border-left:1px solid #c8c8cc;" if i else ""}">{b[0]}</div>' for i, b in enumerate(buttons))
    return f"""<div style="position:absolute;left:46px;right:46px;top:220px;background:rgba(242,242,247,.97);border-radius:16px;
      text-align:center;{IOS}color:#000;overflow:hidden">
      <div style="padding:18px 16px 14px"><div style="font-weight:600;font-size:15px;margin-bottom:4px">{title}</div>
      <div style="font-size:12.5px;line-height:1.35">{body}</div></div>
      <div style="display:flex;border-top:1px solid #c8c8cc;font-size:15px">{btns}</div></div>"""


def ios_phone(inner, bg="#f2f2f7"):
    return f"""<div style="{PHONE.format(bg=bg)}">
  <div style="height:44px;font:600 14px/44px -apple-system,system-ui;padding-left:30px;color:#000">9:41</div>{inner}</div>"""


@image("ios-profile-downloaded", 720, 640, "body{background:#e9edf2}")
def _():
    page = '<div style="position:absolute;inset:44px 0 0;background:#fff"></div><div style="position:absolute;inset:0;background:rgba(0,0,0,.3)"></div>'
    a = ios_phone(page + ios_alert("This website is trying to download a configuration profile. Do you want to allow this?",
                                   "", [("Ignore", False), ("Allow", True)], 'data-hl="1" data-pad="0"'))
    b = ios_phone(page + ios_alert("Profile Downloaded", "Review the profile in the Settings app if you want to install it.",
                                   [("Close", True)], 'data-hl="2" data-pad="0"'))
    return (a + f'<div style="position:absolute;left:360px;top:0">{b}</div>'
            )


@image("ios-settings", 360, 640, "body{background:#e9edf2}")
def _():
    row = lambda t, s="", c="#000": (f'<div style="display:flex;justify-content:space-between;padding:12px 16px;'
                                      f'border-bottom:1px solid #e5e5ea;font-size:15px;color:{c}"><span>{t}</span>'
                                      f'<span style="color:#8e8e93">{s} ›</span></div>')
    inner = f"""<div style="padding:4px 18px 10px;font:700 30px -apple-system,system-ui">Settings</div>
  <div style="margin:0 16px 18px;background:#fff;border-radius:12px;overflow:hidden">
    <div style="display:flex;gap:12px;align-items:center;padding:12px 16px">
      <div style="width:46px;height:46px;border-radius:50%;background:#c7c7cc"></div>
      <div><div style="font-size:17px">Your name</div><div style="font-size:12px;color:#8e8e93">Apple Account, iCloud and more</div></div></div></div>
  <div style="margin:0 16px 18px;background:#fff;border-radius:12px;overflow:hidden"><div data-hl="1" data-pad="2" data-r="12">{row("Profile Downloaded")}</div></div>
  <div style="margin:0 16px;background:#fff;border-radius:12px;overflow:hidden">
    {row("Airplane Mode")}{row("Wi-Fi", "HomeWiFi")}{row("Bluetooth", "On")}{row("Mobile Service")}{row("Battery")}</div>"""
    return ios_phone(inner)


@image("ios-install", 360, 640, "body{background:#e9edf2}")
def _():
    inner = f"""<div style="display:flex;justify-content:space-between;padding:6px 18px 14px;font-size:15px;{IOS}">
    <span style="color:#0a84ff">Cancel</span><b style="font-weight:600">Install Profile</b>
    <span data-hl="1" data-r="8" style="color:#0a84ff;font-weight:600">Install</span></div>
  <div style="margin:4px 16px;background:#fff;border-radius:12px;padding:16px;{IOS}">
    <div style="display:flex;gap:12px;align-items:center;margin-bottom:12px">
      <div style="width:50px;height:50px;border-radius:11px;background:#e8eefc;color:#2d6cdf;font-size:28px;line-height:50px;
           text-align:center">⛨</div>
      <div><div style="font-size:17px;font-weight:600">NextDNS</div><div style="font-size:12.5px;color:#8e8e93">my.nextdns.io</div></div></div>
    <div style="font-size:13px;line-height:1.9;color:#3c3c43"><span style="color:#8e8e93">Contains</span> &nbsp;DNS Settings</div></div>
  <div style="margin:18px 30px;font-size:12.5px;color:#6c6c70;line-height:1.5;{IOS}">Then enter your iPhone passcode, and
    tap <b>Install</b> again on the next screen.</div>"""
    return ios_phone(inner)


@image("ios-private-relay", 360, 640, "body{background:#e9edf2}")
def _():
    inner = f"""<div style="padding:6px 18px 14px;font-size:15px;{IOS}"><span style="color:#0a84ff">‹ iCloud</span></div>
  <div style="padding:0 18px 12px;font:700 26px -apple-system,system-ui">Private Relay</div>
  <div style="margin:0 16px;background:#fff;border-radius:12px;padding:12px 16px;display:flex;justify-content:space-between;
       align-items:center;font-size:15px;{IOS}">Private Relay
    <span data-hl="1" data-r="999" style="width:51px;height:31px;border-radius:999px;background:#e9e9eb;position:relative;display:inline-block">
      <span style="position:absolute;left:2px;top:2px;width:27px;height:27px;border-radius:50%;background:#fff;
            box-shadow:0 2px 4px rgba(0,0,0,.2)"></span></span></div>
  <div style="margin:10px 30px;font-size:12.5px;color:#6c6c70;line-height:1.5;{IOS}">Private Relay hides your browsing in
    Safari — including from NextDNS. Leave it off on this phone.</div>"""
    return ios_phone(inner)


# ---- composed real screenshots -------------------------------------------------
@image("nextdns-android", 640, 408)
def _():
    return f"""<div class="clip" style="left:0;top:0;width:640px;height:408px">
  <img src="{raw('nextdns-android.jpg')}" style="left:0;top:0;width:640px"></div>
{hl(1, 34, 254, 530, 46, 8)}
{hl(2, 34, 330, 310, 30, 8)}"""


# Already annotated when they were captured; copied as they are.
AS_IS = ["mac-profile-downloaded.png", "mac-profile-pending.png", "mac-profile-review.png",
         "mac-profile-installed.png", "nextdns-home.png", "nextdns-parental.png", "nextdns-apple.png"]


AUTO = """<script>
document.querySelectorAll("[data-hl]").forEach(e => {
  const r = e.getBoundingClientRect(), p = +(e.dataset.pad || 5), d = document.createElement("div");
  d.className = "hl";
  d.style.cssText = `left:${r.left-p}px;top:${r.top-p}px;width:${r.width+2*p}px;height:${r.height+2*p}px;` +
                    `border-radius:${e.dataset.r || 10}px`;
  const at = {right: "left:auto;right:-15px", above: "left:auto;right:-6px;top:-28px"}[e.dataset.badge] || "";
  d.innerHTML = `<b style="${at}">${e.dataset.hl}</b>`;
  document.body.appendChild(d);
});
</script>"""


def render(name, w, h, css, body):
    html = (f"<!doctype html><meta charset=utf-8><style>{BASE}{css}</style>"
            f"<body style='width:{w}px;height:{h}px'>{body}{AUTO}")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
    out = OUT / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                    "--force-device-scale-factor=2", f"--window-size={w},{h}", f"--screenshot={out}",
                    "--virtual-time-budget=2000", pathlib.Path(f.name).as_uri()],
                   check=True, capture_output=True)
    pathlib.Path(f.name).unlink()
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    for name, (w, h, css, fn) in IMAGES.items():
        if not only or name in only:
            print("  drew", render(name, w, h, css, fn()).name)
    for name in AS_IS:
        if not only or name.removesuffix(".png") in only:
            # Keep them a sensible size for an offline page.
            subprocess.run(["sips", "-Z", "1200", str(RAW / name), "--out", str(OUT / name)],
                           check=True, capture_output=True)
            print("  copied", name)


if __name__ == "__main__":
    main()
