#!/bin/bash
# Source from a dedicated Bash session; save each key before changing it.
SAVED=$(mktemp)
save() { # save <key>
  if v=$(defaults read NullPlayer "$1" 2>/dev/null); then
    # Restore the ORIGINAL type. Writing a bool back as -string leaves the key readable
    # but re-typed, which is a silent change to the user's preferences.
    case "$(defaults read-type NullPlayer "$1" 2>/dev/null)" in
      # `defaults read` prints a bool as 1/0, but `defaults write -bool` only accepts
      # true|false|yes|no — feeding 1 back is a usage error and the key is NOT restored.
      *boolean*) flag="-bool"; [ "$v" = "1" ] && v=true || v=false ;;
      *integer*) flag="-int" ;;
      *float*)   flag="-float" ;;
      *)         flag="-string" ;;
    esac
    printf 'defaults write NullPlayer %q %s %q\n' "$1" "$flag" "$v" >> "$SAVED"
  else
    printf 'defaults delete NullPlayer %q 2>/dev/null || true\n' "$1" >> "$SAVED"
  fi
}
restore() { bash "$SAVED" 2>/dev/null || true; rm -f "$SAVED"; }
trap restore EXIT
