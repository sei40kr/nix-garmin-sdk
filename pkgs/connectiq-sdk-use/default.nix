# Registers a Nix-built SDK as the "current SDK" in ~/.Garmin/ConnectIQ, the
# same way the SDK Manager does. Editors (e.g. the Monkey C VS Code extension)
# read the SDK from there, while device definitions stay in
# ~/.Garmin/ConnectIQ/Devices, managed by the SDK Manager.
{
  writeShellApplication,
  coreutils,
  gawk,
  connectiq-sdk,
}:

writeShellApplication {
  name = "connectiq-sdk-use";
  runtimeInputs = [
    coreutils
    gawk
  ];
  text = ''
    usage() {
      echo "Usage: connectiq-sdk-use [SDK_ROOT]"
      echo
      echo "Points ~/.Garmin/ConnectIQ/current-sdk.cfg (and the SDK Manager's"
      echo "current-sdk setting) at SDK_ROOT."
      echo "Defaults to ${connectiq-sdk}/${connectiq-sdk.sdkPath}."
    }

    case "''${1:-}" in
      -h | --help) usage; exit 0 ;;
    esac

    sdk="''${1:-${connectiq-sdk}/${connectiq-sdk.sdkPath}}"
    sdk="''${sdk%/}"
    if [ ! -x "$sdk/bin/monkeyc" ]; then
      echo "connectiq-sdk-use: $sdk does not look like a Connect IQ SDK" >&2
      exit 1
    fi

    root="$HOME/.Garmin/ConnectIQ"
    mkdir -p "$root/Devices"

    # The SDK Manager stores the path with a trailing slash.
    cfg="$root/current-sdk.cfg"
    if [ "$(cat "$cfg" 2>/dev/null || true)" != "$sdk/" ]; then
      printf '%s/' "$sdk" > "$cfg"
    fi

    ini="$root/sdkmanager-config.ini"
    if [ -f "$ini" ]; then
      tmp="$(mktemp "$ini.XXXXXX")"
      # Replace or insert current-sdk in the global section (before any [section]).
      awk -v val="$sdk/" '
        BEGIN { done = 0 }
        !done && /^\[/ { print "current-sdk=" val; done = 1 }
        /^current-sdk=/ { if (!done) { print "current-sdk=" val; done = 1 }; next }
        { print }
        END { if (!done) print "current-sdk=" val }
      ' "$ini" > "$tmp"
      mv "$tmp" "$ini"
    else
      printf 'current-sdk=%s/\n' "$sdk" > "$ini"
    fi

    echo "Connect IQ SDK set to $sdk"
  '';
  meta.description = "Make a Nix-built Connect IQ SDK the current SDK for Garmin tools";
}
