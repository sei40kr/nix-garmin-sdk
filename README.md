# nix-garmin-sdk

Nix flake for [Garmin Connect IQ](https://developer.garmin.com/connect-iq/) development on Linux:

| Package                 | Contents                                                                                                                   |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `connectiq-sdk`         | The Connect IQ SDK: `monkeyc`, `monkeydo`, `monkeydoc`, `barrelbuild`, `era`, `connectiq`/`simulator`, … (Java included) |
| `connectiq-sdk-manager` | The Connect IQ SDK Manager (`sdkmanager`), used to log in and download device definitions                                |
| `connectiq-sdk-use`     | Registers the SDK from Nix as the current SDK in `~/.Garmin/ConnectIQ`                                                    |

The SDK is pinned by Nix; device definitions stay under the SDK Manager's control in
`~/.Garmin/ConnectIQ/Devices`, which is where `monkeyc` and the simulator look for them.

Only `x86_64-linux` is supported, because Garmin ships only x86_64 Linux binaries. The SDK is unfree
(Connect IQ SDK License Agreement); this flake's own package set allows it.

## Usage

### Project dev shell

```sh
nix flake init -t github:sei40kr/nix-garmin-sdk
direnv allow   # or: nix develop
```

The dev shell puts the SDK tools and `sdkmanager` on `PATH` and runs `connectiq-sdk-use`, which writes
the SDK's store path to `~/.Garmin/ConnectIQ/current-sdk.cfg` (and the SDK Manager's
`current-sdk` setting). Editors such as the Monkey C VS Code extension then use the Nix SDK.

First-time setup:

1. Run `sdkmanager`, log in with your Garmin developer account, and download the devices you target
   (the **Devices** tab). Downloading SDKs in the SDK Manager is unnecessary.
2. Build and run:

   ```sh
   monkeyc -f monkey.jungle -d fenix7 -y developer_key.der -o bin/app.prg
   connectiq &                       # simulator
   monkeydo bin/app.prg fenix7
   ```

> [!NOTE]
> `current-sdk.cfg` points into `/nix/store`. Keep the SDK rooted (dev shell via nix-direnv,
> `nix profile install`, …) so `nix-collect-garbage` does not remove it; running the dev shell again
> rewrites the path after updates.

### Other ways

```sh
nix run github:sei40kr/nix-garmin-sdk                     # SDK Manager
nix run github:sei40kr/nix-garmin-sdk#connectiq-sdk       # monkeyc
nix profile install github:sei40kr/nix-garmin-sdk#connectiq-sdk github:sei40kr/nix-garmin-sdk#connectiq-sdk-manager
```

Or use `overlays.default` in your own configuration (you must allow the unfree packages
`connectiq-sdk` and `connectiq-sdk-manager` there).

Older SDKs: `connectiq-sdk.override { source = { version = "…"; url = "…"; hash = "…"; }; }`.

## Updating

`sources.json` pins the SDK and SDK Manager archives. `nix run .#update` reads Garmin's feeds
(`sdks.json`, `sdk-manager.json`), prefetches new archives and rewrites `sources.json`;
`--sdk-version X.Y.Z` pins a specific SDK. The **Update sources** GitHub workflow runs it daily,
runs `nix flake check` and opens a pull request.

Garmin publishes the SDK Manager under a fixed URL (`connectiq-sdk-manager-linux.zip`). When it
is replaced upstream, older revisions of this flake can no longer fetch it (hash mismatch) until
`sources.json` is updated.

## How it works

Both the simulator and the SDK Manager are wxGTK programs that need special handling:

- **WebKitGTK 4.0 → 4.1.** They link `libwebkit2gtk-4.0.so.37` (the libsoup2 ABI), which Nixpkgs no
  longer ships. They import no `soup_*` functions, and every `webkit_*`/`JS*` symbol they use exists
  unchanged in the 4.1 ABI, so the build retargets them to `webkitgtk_4_1` and drops `libsoup-2.4`.
- **Embedded FreeType, libpng and libjpeg.** The executables statically contain these libraries and
  export their symbols, so the system libfreetype ended up calling the executable's
  `TT_New_Context` and crashed while rendering glyphs. `pkgs/localize-dynsym.py` marks those
  exports `STB_LOCAL`, which the dynamic linker ignores.
- **TLS.** Nixpkgs' GnuTLS only trusts `/etc/ssl/certs/ca-certificates.crt`, so WebKit (the login
  page) failed with *Unacceptable TLS certificate* on systems that keep the CA bundle elsewhere.
  The wrappers use glib-networking built against OpenSSL and pick one readable CA bundle
  (`SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, the usual distribution paths, then Nixpkgs' `cacert`),
  exported as both `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE`. libcurl, which the SDK Manager uses
  for downloads, uses the same bundle.
- The SDK launch scripts find their siblings through `dirname "$0"`, so `$out/bin` contains wrappers
  (which also put JDK 17 on `PATH`) rather than symlinks.

The SDK Manager's self-update does not work, because the store is read-only; update through this
flake instead.

## Tests

- `nix flake check` builds everything and runs offline smoke tests: `monkeyc --version`,
  `connectiq-sdk-use`, CA bundle selection, a GIO TLS handshake through the bundled backend, and
  starting the simulator and the SDK Manager on Xvfb.
- `tests/check-login-page.sh` (run by CI) starts the SDK Manager on Xvfb, accepts the license,
  clicks **Login** and checks via OCR that Garmin's sign-in page rendered without TLS errors.
  Screenshots are uploaded as workflow artifacts. `nix run .#gui-screenshot -- OUTDIR SECONDS
  PROGRAM` takes screenshots of any GUI.
