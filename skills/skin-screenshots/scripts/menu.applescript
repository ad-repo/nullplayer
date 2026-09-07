-- Drives the Skins / Windows menus. Three verbs:
--   mode <submenu>            click that submenu's "Switch to ..." item if present
--   skin <submenu> <item>     select a skin (does NOT switch system - use mode first)
--   closeaux                  toggle off every checked window except Main Window
-- Selecting a skin name only changes the skin WITHIN the active system. Switching
-- systems requires the "Switch to ..." item, which is only present when you are
-- outside that system. Getting this wrong silently re-photographs the old system.
on run argv
  set act to item 1 of argv
  tell application "System Events"
    tell process "NullPlayer"
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
            key code 53
            return closed
          end if
          set closed to closed & (item hit of nms) & ","
          click menu item hit of mm
          delay 0.7
        end repeat
        -- Some skins declare windows that cannot be closed (fixed EQ/playlist).
        -- Give up rather than loop: the main window shot is still valid.
        key code 53
        return closed & "(gave-up)"

      else if act is "mode" then
        set subName to item 2 of argv
        click menu bar item "Skins" of menu bar 1
        delay 0.4
        click menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        delay 0.5
        set sm to menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        set nms to name of every menu item of sm
        repeat with i from 1 to count of nms
          set nm to item i of nms
          if nm is not missing value then
            if nm starts with "Switch to" then
              click menu item i of sm
              return "switched:" & nm
            end if
          end if
        end repeat
        key code 53
        delay 0.2
        key code 53
        return "already"

      else if act is "list" then
        set subName to item 2 of argv
        click menu bar item "Skins" of menu bar 1
        delay 0.4
        click menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        delay 0.6
        set nms to name of every menu item of menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        key code 53
        delay 0.2
        key code 53
        return nms

      else if act is "skin" then
        set subName to item 2 of argv
        set skinName to item 3 of argv
        click menu bar item "Skins" of menu bar 1
        delay 0.4
        click menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        delay 0.5
        click menu item skinName of menu 1 of menu item subName of menu 1 of menu bar item "Skins" of menu bar 1
        return "ok"
      end if
    end tell
  end tell
end run
