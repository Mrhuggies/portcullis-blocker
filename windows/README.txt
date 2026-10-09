PORTCULLIS FOR WINDOWS
======================

Blocks adult websites in every browser and app on this PC, plus any sites
you add yourself. Adding a block is instant. Taking one off waits 48 hours
(you can make that longer).

UNTESTED ON REAL WINDOWS. The rules and the control panel are tested; the
parts that only exist on Windows (the permission prompt, the scheduled
watchdog, the Chrome/Edge settings) have not yet been run on a real PC.
Everything it changes can be undone - see "Removing it" below.


GETTING STARTED
---------------
1. Move this folder somewhere permanent, such as Documents. The panel runs
   from here.

2. Double-click Portcullis.cmd.
   If Windows shows "Windows protected your PC", click "More info" and then
   "Run anyway". That warning appears for any program that isn't from a
   registered publisher; this one is plain text you can read.

3. Your browser opens the panel. Click "Turn on" and say Yes when Windows
   asks for permission.

The first time, this also installs a watchdog that puts the block back if
anything removes it, and stops Chrome and Edge from switching it off.


WHAT IT CHANGES
---------------
- C:\Windows\System32\drivers\etc\hosts - the block list, between two
  "portcullis" marker lines. Anything else in the file is left alone, and a
  backup is taken first.
- C:\ProgramData\Portcullis - the watchdog and its copy of the list.
- A scheduled task called "Portcullis Guard" (checks every 5 minutes).
- Chrome and Edge policies: blocks the 1,000 biggest adult sites inside
  the browser, and turns off "secure DNS", which would skip the hosts file.
- Your own list is saved in %APPDATA%\Portcullis.

Nothing is sent anywhere. The panel only answers this computer.


STEP-BY-STEP GUIDE
------------------
Every screen you'll see, with pictures - including setting up your phone:
open the panel, then Set up > Open the full guide. Or open app\ui\guide.html
in your browser.


REMOVING IT
-----------
Deliberately not a button. Open PowerShell as Administrator, go to this
folder, and run:

    powershell -ExecutionPolicy Bypass -File .\app\windows\uninstall.ps1

Once to ask, and again 48 hours later to confirm. To call it off:

    powershell -ExecutionPolicy Bypass -File .\app\windows\uninstall.ps1 -Cancel

Deleting this folder does NOT remove the blocks - it only removes the panel.
