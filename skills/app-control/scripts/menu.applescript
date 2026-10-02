-- Drives the Skins / Windows menus of ONE process, addressed by unix id. Verbs:
--   mode <pid> <submenu>          click that submenu's "Switch to ..." item if present
--   skin <pid> <submenu> <item>   select a skin; switches into that family when another is on screen
--   list <pid> <submenu>          the submenu's item names
--   current <pid> <submenu>       the checked (loaded) skin in that submenu, or empty
--   family <pid>                  the checked Skins submenu, i.e. the family on screen
--   load <pid> <submenu> <path>   press that submenu's Load ... Skin... and open <path> in its panel
--   closeaux <pid>                toggle off every checked window except Main Window
--   windowitems <pid>             one line per window-toggle item: index|name|enabled|checked
--   toggle <pid> <index> <name>   click Windows item <index>, refusing if its name is not <name>
--
-- `windowitems` reads block 1 of the Windows menu up to its first separator, minus Main Window,
-- Debug Console and Recreate Windows (Debug) (a modal alert), then the next block only when it is a
-- `.wal` skin's own windows, i.e. when it does not open with Compact Mode or Always On Top. `index`
-- is the item's position in the menu as read; the menu is rebuilt on every open, so `toggle`
-- re-checks the name.
--
-- The pid is required and there is no name fallback. `process "NullPlayer"` is ambiguous
-- whenever the installed /Applications build is also running, and resolving it by name is
-- how the installed app gets driven by accident. Pass the pid of the debug build you
-- launched: see `app-control` Rule zero.
-- **Menus are closed through Accessibility, never with Escape.** A menu opened by an AX click on
-- a background app stays open until that app is told to cancel it; `key code 53` goes to the
-- *frontmost* app (the terminal), so the menu stayed up, held the app in menu tracking, and every
-- later toggle silently did nothing (2026-09-27, alongside a hung Finder and Dock). And any
-- error half-way through a verb — a skin or submenu name that is not there — left its menu open
-- the same way, so the verb runs inside `try` and closes every menu before re-raising.
on closeMenus(targetPid)
  tell application "System Events"
    tell (first process whose unix id is targetPid)
      repeat with mbi in menu bar items of menu bar 1
        try
          perform action "AXCancel" of menu 1 of mbi
        end try
      end repeat
    end tell
  end tell
end closeMenus

on run argv
  if (count of argv) < 2 then
    error "menu.applescript: a target pid is required (app-control Rule zero: drive the debug build you launched, never `process \"NullPlayer\"` by name)" number 1
  end if
  set targetPid to (item 2 of argv) as integer
  try
    return drive(argv, targetPid)
  on error msg number n
    closeMenus(targetPid)
    error msg number n
  end try
end run

on drive(argv, targetPid)
  set act to item 1 of argv
  tell application "System Events"
    tell (first process whose unix id is targetPid)
      if act is "closeaux" then
        set closed to ""
        repeat 3 times
          click menu bar item "Windows" of menu bar 1
          delay 0.35
          set mm to menu 1 of menu bar item "Windows" of menu bar 1
          set nms to name of every menu item of mm
          set mks to value of attribute "AXMenuItemMarkChar" of every menu item of mm
          set hit to 0
          repeat with i from 1 to count of nms
            set nm to item i of nms
            set mk to item i of mks
            if nm is not missing value and nm is not "Main Window" then
              if mk is not missing value and mk is not "" then
                set hit to i
                exit repeat
              end if
            end if
          end repeat
          if hit is 0 then
            my closeMenus(targetPid)
            return closed
          end if
          set closed to closed & (item hit of nms) & ","
          click menu item hit of mm
          delay 0.7
        end repeat
        -- Some skins declare windows that cannot be closed (fixed EQ/playlist).
        -- Give up rather than loop: the main window shot is still valid.
        my closeMenus(targetPid)
        return closed & "(gave-up)"

      else if act is "windowitems" then
        click menu bar item "Windows" of menu bar 1
        delay 0.35
        set mm to menu 1 of menu bar item "Windows" of menu bar 1
        set nms to name of every menu item of mm
        set ens to enabled of every menu item of mm
        set mks to value of attribute "AXMenuItemMarkChar" of every menu item of mm
        my closeMenus(targetPid)
        set out to {}
        set blockNo to 1
        set n to count of nms
        set i to 1
        repeat while i ≤ n
          set nm to item i of nms
          if nm is missing value or nm is "" then
            -- A separator ends block 1; the next block counts only if it is a .wal skin's windows.
            if blockNo is 2 or i = n then exit repeat
            set nx to item (i + 1) of nms
            if nx is "Compact Mode" or nx is "Always On Top" then exit repeat
            set blockNo to 2
          else if nm is not "Main Window" and nm is not "Recreate Windows (Debug)" and nm is not "Debug Console" then
            set mk to item i of mks
            if mk is missing value or mk is "" then
              set ck to "0"
            else
              set ck to "1"
            end if
            if item i of ens then
              set en to "1"
            else
              set en to "0"
            end if
            set end of out to (i as text) & "|" & nm & "|" & en & "|" & ck
          end if
          set i to i + 1
        end repeat
        set AppleScript's text item delimiters to linefeed
        return out as text

      else if act is "toggle" then
        set idx to (item 3 of argv) as integer
        set want to item 4 of argv
        -- AXPress on the item with the menu closed. Opening the menu and `click`ing the item left
        -- the menu up with nothing run (2026-09-28): the item fired only when pressed unopened.
        set mm to menu 1 of menu bar item "Windows" of menu bar 1
        set nm to name of menu item idx of mm
        if nm is not want then
          error "menu.applescript toggle: Windows item " & idx & " is '" & nm & "', not '" & want & "'" number 2
        end if
        perform action "AXPress" of menu item idx of mm
        return "ok"

      -- The Skins verbs read and press the submenus unopened, as `toggle` does: opening the menu
      -- and `click`ing a skin left the menu up with the selection highlighted and nothing run
      -- (2026-10-02), while `AXPress` on the unopened item fires it.
      else if act is "mode" then
        set subName to item 3 of argv
        set sm to menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        set nms to name of every menu item of sm
        repeat with i from 1 to count of nms
          set nm to item i of nms
          if nm is not missing value then
            if nm starts with "Switch to" then
              perform action "AXPress" of menu item i of sm
              return "switched:" & nm
            end if
          end if
        end repeat
        return "already"

      else if act is "list" then
        set subName to item 3 of argv
        return name of every menu item of menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1

      else if act is "current" then
        -- The checked skin in a submenu: which skin a mode switch landed on. Every family submenu
        -- lists its skins after its last divider (`buildSkinFamilyMenu`), so only that block is
        -- read: options above it are checked too, such as "Reimport ClassicPro Engine...".
        set subName to item 3 of argv
        set sm to menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        set nms to name of every menu item of sm
        set mks to value of attribute "AXMenuItemMarkChar" of every menu item of sm
        set found to ""
        repeat with i from 1 to count of nms
          set nm to item i of nms
          if nm is missing value or nm is "" then
            set found to ""
          else
            set mk to item i of mks
            if mk is not missing value and mk is not "" then set found to nm
          end if
        end repeat
        return found

      else if act is "family" then
        -- The checked Skins submenu: the family on screen.
        set m to menu 1 of menu bar item "Skins" of menu bar 1
        set nms to name of every menu item of m
        set mks to value of attribute "AXMenuItemMarkChar" of every menu item of m
        repeat with i from 1 to count of nms
          set mk to item i of mks
          if mk is not missing value and mk is not "" then return item i of nms
        end repeat
        return ""

      else if act is "load" then
        -- Press the submenu's "Load ... Skin..." item and answer its open panel with <path>. The
        -- panel is modal, so the press is sent without waiting for a reply; the path goes in
        -- through the panel's Go To field, which needs the build frontmost to receive keystrokes.
        set subName to item 3 of argv
        set filePath to item 4 of argv
        set sm to menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        set nms to name of every menu item of sm
        set hit to 0
        repeat with i from 1 to count of nms
          set nm to item i of nms
          if nm is not missing value then
            if nm starts with "Load" then
              set hit to i
              exit repeat
            end if
          end if
        end repeat
        if hit is 0 then error "menu.applescript load: no Load item in " & subName number 2
        ignoring application responses
          perform action "AXPress" of menu item hit of sm
        end ignoring
        set panelUp to false
        repeat 40 times
          delay 0.25
          if exists (first window whose role description is "dialog") then
            set panelUp to true
            exit repeat
          end if
        end repeat
        if not panelUp then error "menu.applescript load: no open panel appeared" number 3
        set frontmost to true
        delay 0.4
        if not frontmost then error "menu.applescript load: build is not frontmost; refusing to type" number 4
        keystroke "g" using {command down, shift down}
        delay 0.8
        keystroke filePath
        delay 0.5
        -- The first Return goes to the path, the second presses Open once the Go To sheet has gone.
        set dlg to first window whose role description is "dialog"
        key code 36
        repeat 20 times
          if not (exists sheet 1 of dlg) then exit repeat
          delay 0.1
        end repeat
        if exists sheet 1 of dlg then error "menu.applescript load: the Go To sheet did not close" number 5
        key code 36
        repeat 40 times
          if not (exists (first window whose role description is "dialog")) then return "ok"
          delay 0.25
        end repeat
        error "menu.applescript load: the open panel did not close" number 6

      else if act is "skin" then
        set subName to item 3 of argv
        set skinName to item 4 of argv
        perform action "AXPress" of menu item skinName of menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        return "ok"
      end if
    end tell
  end tell
end drive
