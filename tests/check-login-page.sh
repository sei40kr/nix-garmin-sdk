#!/usr/bin/env bash
# Online check of the SDK Manager: start it with a fresh HOME, accept the
# license agreement if asked, press "Login" and verify with OCR that Garmin's
# sign-in page rendered (i.e. WebKit works and TLS verification succeeded).
#
# Usage: tests/check-login-page.sh SDKMANAGER OUTDIR
# Needs connectiq-gui-screenshot (nix run .#gui-screenshot) on PATH.
set -euo pipefail

sdkmanager=$1
outdir=$2

# Window positions are fixed: Xvfb has no window manager, so every toplevel
# opens at 0,0 with its default size.
export GUI_TEST_ACTION='
  if xdotool search --name "License Agreement" >/dev/null 2>&1; then
    xdotool mousemove 22 513 click 1; sleep 1
    xdotool mousemove 447 573 click 1; sleep 8
  fi
  xdotool mousemove 385 240 click 1
'

status=0
connectiq-gui-screenshot "$outdir" "${LOGIN_CHECK_SECONDS:-50}" "$sdkmanager" || status=$?

last=$(find "$outdir" -name 'shot-*.txt' | sort -V | tail -n 1)
if [ "$status" -ne 0 ]; then
  echo "FAIL: sdkmanager exited early" >&2
  exit 1
fi
if grep -Eqi 'unacceptable|tls error|tls/ssl|certificate' "$outdir"/shot-*.txt; then
  echo "FAIL: TLS error shown" >&2
  exit 1
fi
if ! grep -q "SDK Manager Login" "$outdir/windows.txt"; then
  echo "FAIL: login window did not open" >&2
  exit 1
fi
if ! grep -Eqi "${LOGIN_CHECK_PATTERN:-sign in|email|password}" "$last"; then
  echo "FAIL: sign-in page not recognised in $(basename "$last")" >&2
  exit 1
fi
echo "OK: Garmin sign-in page rendered"
