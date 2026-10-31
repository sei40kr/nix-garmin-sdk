# nix-garmin-sdk

Nix flake for [Garmin Connect IQ](https://developer.garmin.com/connect-iq/) development on `x86_64-linux`.

| Package                          | Contents                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| `connectiq-sdk_<major>_<minor>`  | The newest patch release of each SDK line, e.g. `connectiq-sdk_9_3` = 9.3.0                 |
| `connectiq-sdk`                  | The newest SDK                                                                              |
| `connectiq-sdk-manager`          | The SDK Manager (`sdkmanager`), used to download device files and fonts                     |

Each SDK package provides these commands, with Java included:

- `monkeyc`: compiles a Monkey C project
- `monkeydo`: runs a compiled app in the simulator
- `connectiq`: starts the simulator
- `mdd`: debugs a compiled app in the simulator
- `monkeydoc`: generates API documentation
- `barrelbuild`: builds a Monkey Barrel (library)
- `barreltest`: compiles a Monkey Barrel's unit tests
- `era`: downloads crash reports from the Error Reporting App
- `monkeygraph`: plots FIT files
- `monkeymotion`: the Monkey Motion GUI, which converts videos to animations
- `monkeym`: the Monkey Motion command-line converter

The SDKs are unfree. The flake builds its packages with `allowUnfree`, so consumers need no extra
configuration.

## Usage

Nix pins the SDK. Device files and fonts require a Garmin login, so the SDK Manager downloads them
into `~/.Garmin/ConnectIQ/{Devices,Fonts}`, where every SDK package looks for them.

1. Run `nix run github:sei40kr/nix-garmin-sdk#connectiq-sdk-manager`, log in, and download the
   devices you target from the **Devices** tab.

   > [!WARNING]
   > Do not download SDKs there; they do not run on NixOS (see
   > [SDKs downloaded by the SDK Manager](#sdks-downloaded-by-the-sdk-manager)).
2. Add an SDK to your project's dev shell:

   ```nix
   {
     inputs.garmin-sdk.url = "github:sei40kr/nix-garmin-sdk";

     outputs =
       { nixpkgs, garmin-sdk, ... }:
       let
         pkgs = nixpkgs.legacyPackages.x86_64-linux;
       in
       {
         devShells.x86_64-linux.default = pkgs.mkShell {
           packages = [ garmin-sdk.packages.x86_64-linux.connectiq-sdk_9_3 ];
         };
       };
   }
   ```

3. Build and run:

   ```sh
   monkeyc -d fr965 -f monkey.jungle -o app.prg -y developer_key.der
   connectiq &          # start the simulator
   monkeydo app.prg fr965
   ```

Device files follow the newest SDK. An older SDK line refuses a device whose files require a newer
API level, e.g. SDK 8.1 cannot build for the current `fr965` files (API 5.2.0).

## Updating

```sh
nix run .#connectiq-sdk.updateScript
```

The script regenerates `sources.json` from Garmin's `sdks.json` and `sdk-manager.json`. It keeps
the newest patch release of each major.minor line and downloads only archives whose file names
changed. SDK archive names contain a build ID, so a name pins its content. The SDK Manager is only
published under an unversioned URL, which always serves the latest release.

## Workarounds

### webkit2gtk-4.0

The simulator, `monkeymotion` and `sdkmanager` link against `libwebkit2gtk-4.0.so.37`,
`libjavascriptcoregtk-4.0.so.18` and `libsoup-2.4.so.1`, which nixpkgs has removed. None of them
calls libsoup directly, and every webkit and JavaScriptCore symbol they use also exists in 4.1.
[`webkitgtk-4.0-compat.nix`](packages/connectiq-sdk/webkitgtk-4.0-compat.nix) provides symlinks
with the 4.0 names that point to `webkitgtk_4_1` and `libsoup_3`, and `autoPatchelfHook` links the
binaries against them.

The binaries are patched rather than started through `ld.so --library-path`. They find their
resources in `../share/<name>` relative to `/proc/self/exe`, which would point at the loader instead.

The SDK Manager's login page needs `glib-networking` for TLS; without it, it fails with
"TLS support is not available".

### default.jungle

`monkeyc` generates `default.jungle` (about 3800 lines that map every device to its resource paths)
in the directory that contains `monkeybrains.jar`. In the store that directory is read-only, so
`monkeyc` fails with `Unable to generate default.jungle: Read-only file system`.

Every command in `bin/` is a symlink to [`launcher.sh`](packages/connectiq-sdk/launcher.sh). For the
Java tools, the launcher:

1. Creates a per-user copy of the SDK in
   `${XDG_CACHE_HOME:-~/.cache}/connectiq-sdk/<store path name>/`. Everything in it is a symlink
   to the store except `bin/monkeybrains.jar`, which is copied, because Java resolves symlinks on
   the classpath and would otherwise write next to the store copy.
2. Deletes the cached `default.jungle` when the Devices directory changes. `monkeyc` generates the
   file only when it is missing, so without this step it would never see devices that the SDK
   Manager adds or updates. The launcher keeps a checksum of the paths, sizes and modification
   times two levels deep in `devices.stamp` at the root of the copy, a file of this flake's own
   that Garmin's tools ignore. It honours `sdkmanager-download-location.cfg` like `monkeyc` does.
3. Runs the tool from the copy.

`connectiq` and `monkeymotion` start directly from the store.

Each SDK store path leaves about 23 MB in `~/.cache/connectiq-sdk`. Old copies are not removed
automatically. Deleting the directory is safe; the launcher recreates the copies it needs.

### SDKs downloaded by the SDK Manager

SDKs downloaded by the SDK Manager contain unpatched binaries and need an FHS environment to run.
The SDK packages here run the simulator directly, so the flake provides no FHS wrapper, and the
SDK Manager is only used for devices and fonts.

## Known issues

- The SDK Manager allows only one running instance. If one is already running, a new `sdkmanager`
  exits immediately with status 0.
- The simulator keeps state in `$TMPDIR/com.garmin.connectiq` (`/tmp` by default). Once that state
  goes bad, `monkeydo` prints nothing and
  `GARMIN/APPS/LOGS/CIQ_LOG.YML` records `Signature check failed`. Starting the simulator
  with an empty state directory fixes it, e.g. `TMPDIR=$(mktemp -d) connectiq`.
- The Monkey C VS Code extension finds the SDK through `~/.Garmin/ConnectIQ/current-sdk.cfg`. Using
  it with these packages is untested.
