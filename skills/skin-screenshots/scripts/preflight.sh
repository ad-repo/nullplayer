#!/bin/bash
# Refuses to start a sweep in a state that silently produces bad frames.
# Every check here exists because it went wrong in a real run.
cd "$(dirname "$0")"
fail=0
pid=$(pgrep -x NullPlayer | head -1)
if [ -z "$pid" ]; then echo "FAIL  NullPlayer is not running"; exit 1; fi
echo "pid $pid"

# 1. Scheduling priority. A binary launched with nohup from an agent shell inherits
#    background QoS + nice>0: the UI throttles, timers defer, skins take seconds longer
#    to settle and the spectrum stops animating. Must be launched from a real terminal.
ni=$(ps -o nice= -p "$pid" | tr -d ' ')
if [ "${ni:-0}" -ne 0 ]; then
  echo "FAIL  nice=$ni - app is deprioritised. Relaunch it from YOUR terminal, not via the agent:"
  echo "        pkill -9 -x NullPlayer && ./scripts/kill_build_run.sh --debug"
  fail=1
else echo "ok    nice=0"; fi

# 2. Accessibility / menu bar reachable.
if osascript -e 'tell application "System Events" to tell process "NullPlayer" to get name of menu bar item "Skins" of menu bar 1' >/dev/null 2>&1
then echo "ok    Skins menu reachable"; else echo "FAIL  menu bar unreachable (Accessibility permission?)"; fail=1; fi

# 3. Exactly one window. More than one means aux windows are open.
n=$(./winhelper windows | awk -F'\t' '$2==0 && $7>0' | wc -l | tr -d ' ')
echo "$( [ "$n" -eq 1 ] && echo ok || echo warn )    $n on-screen window(s)"

# 4. Things this CANNOT check - the operator must confirm by looking:
cat <<'NOTE'

  Cannot be verified programmatically - CHECK THESE ON SCREEN FIRST:
    * volume is up and not muted   (volume lives in the state file, written on quit;
                                    it is not in UserDefaults and cannot be read live,
                                    and Up/Down volume keys only work in Classic)
    * a track is PLAYING           (so the display, time and spectrum are alive)
    * the spectrum analyzer is on
    * the playlist is loaded       (skins with an embedded playlist pane show it)

  A skin can mute playback on load - its own volume control may be at zero, and the
  mute then persists into every skin loaded after it. HeadAMP did exactly this. If the
  volume drops mid-sweep, the log position names the culprit; re-shoot from there.
NOTE
exit $fail
