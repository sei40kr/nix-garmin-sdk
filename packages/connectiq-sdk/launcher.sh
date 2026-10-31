#!@runtimeShell@
set -euo pipefail

sdk=@sdk@
tool="${0##*/}"
export PATH="@binPath@${PATH:+:$PATH}"

case "$tool" in
  connectiq | monkeymotion)
    exec "$sdk/bin/$tool" "$@"
    ;;
esac

# monkeyc writes bin/default.jungle next to monkeybrains.jar, which is
# read-only in the store. Java resolves symlinks in the classpath, so run the
# tools from a per-user copy of the SDK where only that jar is a real file.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/connectiq-sdk"
root="$cache/@name@"
if [[ ! -e "$root/bin/monkeybrains.jar" ]]; then
  mkdir -p "$cache"
  tmp="$(mktemp -d "$cache/.tmp.XXXXXX")"
  for f in "$sdk"/*; do
    [[ "${f##*/}" == bin ]] || ln -s "$f" "$tmp/"
  done
  mkdir "$tmp/bin"
  for f in "$sdk"/bin/*; do
    [[ "${f##*/}" == monkeybrains.jar ]] || ln -s "$f" "$tmp/bin/"
  done
  cp --reflink=auto "$sdk/bin/monkeybrains.jar" "$tmp/bin/"
  # Another process may have finished the same copy first
  mv -T "$tmp" "$root" 2>/dev/null || rm -rf "$tmp"
fi

# monkeyc only generates default.jungle when it is missing, so it would never
# pick up devices added or updated by the SDK Manager on its own.
garmin="$HOME/.Garmin/ConnectIQ"
devices="$garmin/Devices"
if [[ -r "$garmin/sdkmanager-download-location.cfg" ]]; then
  read -r location <"$garmin/sdkmanager-download-location.cfg" || true
  devices="${location}Devices"
fi
stamp="$({ find -L "$devices" -maxdepth 2 -printf '%p %s %T@\n' 2>/dev/null || true; } | sort | cksum)"
if [[ "$(cat "$root/devices.stamp" 2>/dev/null)" != "$stamp" ]]; then
  rm -f "$root/bin/default.jungle"
  printf '%s\n' "$stamp" >"$root/devices.stamp"
fi

exec "$root/bin/$tool" "$@"
