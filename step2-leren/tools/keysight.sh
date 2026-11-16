#!/bin/bash
# KeySight launcher for the Steam Frame. Put it next to KeySight.arm64 and add THIS script to
# Steam as a non-Steam game. It installs a staged update, applies the refresh rate chosen in
# the app (button "Hz") as SteamVR per-app preference, and writes a log next to the app.
here=$(dirname "$(readlink -f "$0")")
cd "$here"
mkdir -p "$here/songs"
# Staged update (cannot be replaced while the app runs).
if [ -f "$here/KeySight.arm64.new" ]; then
  mv -f "$here/KeySight.arm64.new" "$here/KeySight.arm64"
  chmod +x "$here/KeySight.arm64"
fi
# Refresh rate chosen in KeySight -> SteamVR preference for this app (applies from this start).
vrcmd=/opt/steamvr/bin/linuxarm64/vrcmd
if [[ -n ${SteamAppId:-} && -x $vrcmd && -f "$here/keysight_hz.txt" ]]; then
  hz=$(tr -dc '0-9' < "$here/keysight_hz.txt")
  if [[ $hz == 72 || $hz == 90 || $hz == 120 ]]; then
    LD_LIBRARY_PATH=${vrcmd%/*} "$vrcmd" --set-settings-float "steam.app.$SteamAppId.preferredRefreshRate" "$hz" >/dev/null 2>&1 || true
  fi
fi
{
  echo "=== start $(date -Is) ==="
  "$here/KeySight.arm64" "$@"
  echo "=== exit code $? at $(date -Is) ==="
} 2>&1 | grep --line-buffered -v -e "snd_rawmidi_read error" -e "midi_driver_alsamidi.cpp" > "$here/keysight_last_run.log"
