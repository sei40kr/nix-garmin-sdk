# Run a GUI program on a virtual X display with a throwaway HOME, take
# screenshots, OCR them and collect the program's log.
#
# Usage: connectiq-gui-screenshot OUTDIR SECONDS PROGRAM [ARGS...]
#
# GUI_TEST_ACTION, if set, is evaluated once after the first screenshot (e.g.
# "xdotool mousemove 385 240 click 1" to press a button).
#
# Writes OUTDIR/{log.txt,shot-N.png,shot-N.txt,windows.txt}. Exits non-zero if
# the program died before the end of the observation period.

outdir=$1
seconds=$2
shift 2
mkdir -p "$outdir"
outdir=$(realpath "$outdir")

export HOME="${GUI_TEST_HOME:-$(mktemp -d)}"
mkdir -p "$HOME"

display=:$((90 + RANDOM % 100))
Xvfb "$display" -screen 0 1280x900x24 -nolisten tcp >"$outdir/xvfb.log" 2>&1 &
xvfb=$!
trap 'kill "$xvfb" 2>/dev/null || true' EXIT
for _ in $(seq 50); do
  [ -e "/tmp/.X11-unix/X${display#:}" ] && break
  sleep 0.1
done
export DISPLAY=$display

dbus_conf="$(dirname "$(command -v dbus-daemon)")/../share/dbus-1/session.conf"
dbus-run-session --config-file="$dbus_conf" -- "$@" >"$outdir/log.txt" 2>&1 &
app=$!

status=0
shot=0
for t in $(seq 1 "$seconds"); do
  sleep 1
  if ! kill -0 "$app" 2>/dev/null; then
    rc=0
    wait "$app" || rc=$?
    echo "program exited after ${t}s with status $rc" | tee -a "$outdir/log.txt"
    status=1
    break
  fi
  if [ $((t % 10)) -eq 0 ] || [ "$t" -eq "$seconds" ]; then
    shot=$((shot + 1))
    import -window root "$outdir/shot-$shot.png"
    tesseract "$outdir/shot-$shot.png" "$outdir/shot-$shot" >/dev/null 2>&1 || true
    if [ "$shot" -eq 1 ] && [ -n "${GUI_TEST_ACTION:-}" ]; then
      eval "$GUI_TEST_ACTION"
    fi
  fi
done

xdotool search --onlyvisible --name '.' getwindowname %@ >"$outdir/windows.txt" 2>/dev/null || true
kill "$app" 2>/dev/null || true
wait "$app" 2>/dev/null || true

echo "== windows"
cat "$outdir/windows.txt"
echo "== log"
cat "$outdir/log.txt"
for f in "$outdir"/shot-*.txt; do
  [ -e "$f" ] || continue
  echo "== OCR $(basename "$f")"
  tr -s '[:space:]' ' ' <"$f"
  echo
done
exit "$status"
