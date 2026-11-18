Wheelhouse - a mouse utility for your Mac (macOS 13 Ventura or newer)
=====================================================================

WHAT IT DOES
- Smooth scrolling for regular mouse wheels: each notch glides instead of jumping.
  Set distance, glide time and acceleration, or turn smoothing off and pick
  lines per notch. Reverse vertical / horizontal separately.
- Hold a key while scrolling: Shift = sideways, Option = slower (defaults);
  Command / Control can be set to faster, slower, sideways or zoom.
- Cursor: set speed with acceleration turned fully off (1:1 movement), or keep
  acceleration and set its amount.
- Extra mouse buttons (middle, back, forward, buttons 6-10): give each a click
  action and a drag action, optionally only while holding Ctrl/Option/Shift/Cmd.
  Actions: keyboard shortcut, Mission Control, app windows, switch Space
  left/right, show desktop, back, forward, or "Open or run" (a web link, file,
  app, .sh/.command/.py script, or "shortcut:Name" to run a Shortcuts shortcut).
  Drag modes: drag to scroll (pan), or gestures (up/down/left/right).
  Defaults: middle = drag to scroll; back = Back, drag up/down/left/right for
  Mission Control / app windows / Spaces; forward = Forward.
- Exception apps: switch scrolling and/or buttons off for chosen apps (games...).
- Key swaps: make one key type another, everywhere.
- Report-rate meter (how many times per second your mouse reports).
- Export / import settings as a file, reset everything, start at login,
  hide the menu bar icon (open the app again to get the settings back).
- Trackpads and Magic Mouse are left alone.

HOW TO BUILD AND RUN
1. Unzip. Open Terminal, type `cd ` (with a space), drag the unzipped
   wheelhouse folder onto the Terminal window, press Return.
2. Run:  bash build.sh
   If it says swiftc is missing, run `xcode-select --install`, wait for it
   to finish, then run bash build.sh again. Building takes about a minute.
3. Drag build/Wheelhouse.app into your Applications folder and open it.
   A small mouse icon appears in the menu bar.
4. macOS asks for Accessibility access: System Settings > Privacy & Security >
   Accessibility > turn on Wheelhouse. It starts working within 2 seconds.

NOTES
- If you rebuild, macOS treats it as a new app: in the Accessibility list,
  remove Wheelhouse with the minus button and turn it on again.
- Turn off other mouse tools (Logi Options+, Mos, etc.) to avoid two apps
  fighting over the scroll wheel.
- Settings are saved automatically. To uninstall: quit from the menu bar
  icon and drag Wheelhouse to the Trash.
- Space switching uses the standard Control+arrow shortcuts, so they must be
  on in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
