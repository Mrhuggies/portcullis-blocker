# Portcullis

Free porn blocking for Mac and Windows, with a guide for your phone. Adding a block is
instant; taking one off takes a 48-hour wait, because most urges fade long before then.

**[Download for Mac](https://github.com/Mrhuggies/portcullis-blocker/releases/latest/download/Portcullis-Mac.zip)** ·
**[Download for Windows](https://github.com/Mrhuggies/portcullis-blocker/releases/latest/download/Portcullis-Windows.zip)** ·
**[Step-by-step setup guide](https://mrhuggies.github.io/portcullis-blocker/guide.html)** ·
**[Website](https://mrhuggies.github.io/portcullis-blocker/)**

> **Windows is untested.** The rules and the control panel are covered by the same automated
> tests as the Mac version, but the Windows-only parts — the permission prompt, the scheduled
> watchdog and the Chrome/Edge settings — haven't yet been run on a real PC. Everything it
> changes can be undone, and the hosts file is backed up first.

## What it does

- **Blocks about 77,000 adult sites in every browser and app** on the computer, through the
  system's hosts file — plus any sites you add, and download sites for tools people use to get
  around blocks (Tor, VPNs, proxies).
- **A watchdog** puts the block back if anything removes it.
- **Locks Chrome (and Edge on Windows)** so the browser can't look sites up in a way that skips
  the block.
- **A control panel** in your browser to add sites, switch bypass-tool blocking on, and change
  the waiting period. Tightening is instant; loosening always waits.
- **Phones** are covered by a free NextDNS setup — the guide walks through Android and iPhone
  screen by screen.

Nothing is sent anywhere. The panel only answers your own computer, and there's no account.

## Getting started

1. Download the zip for your computer and unzip it.
2. **Mac:** drag Portcullis into Applications and open it. macOS will refuse the first time —
   go to System Settings → Privacy & Security → *Open Anyway*.
   **Windows:** unzip into Documents and double-click `Portcullis.cmd`. If Windows warns you,
   choose *More info → Run anyway*.
3. Press **Turn on** and approve the password / permission prompt.
4. Open the **Set up** tab for the rest — the Chrome lock on Mac, your phone, and how removal works.

The [setup guide](https://mrhuggies.github.io/portcullis-blocker/guide.html) shows every screen.

## Removing it

Deliberately slow, and deliberately documented: ask once, wait 48 hours, confirm.

```bash
# Mac
sudo bash /Applications/Portcullis.app/Contents/Resources/mac/uninstall-hosts.sh
```

```powershell
# Windows — PowerShell as administrator, in the Portcullis folder
powershell -ExecutionPolicy Bypass -File .\app\windows\uninstall.ps1
```

## Honest limits

- It blocks whole sites by name. It can't see porn inside sites like Reddit or X.
- Someone with the admin password and 48 hours can remove it — that's the design, not a flaw.
- Tor, once installed, routes around everything; Portcullis stops it being downloaded.
- The apps aren't signed by Apple or Microsoft, which is why both systems warn on first launch.

## Building from source

```bash
bash build-app.sh        # Mac app — runs the tests first
bash build-windows.sh    # Windows zip — needs PowerShell (pwsh) for its tests
```

`mac/` and `windows/` also hold stand-alone scripts that set up the same layers by hand.
Guide images are built by `guide/make-images.py`; its raw screenshots aren't published because
some showed personal details before they were covered.

The block list comes from [StevenBlack/hosts](https://github.com/StevenBlack/hosts) (MIT) — see
[THIRD-PARTY-LICENSE.txt](THIRD-PARTY-LICENSE.txt).
