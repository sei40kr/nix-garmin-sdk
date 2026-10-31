{ pkgs, perSystem, ... }:
(pkgs.callPackage ./package.nix {
  inherit (perSystem.self.connectiq-sdk) webkitgtk_4_0-compat;
  source = (pkgs.lib.importJSON ../../sources.json).sdkManager;
}).overrideAttrs
  (old: {
    # The same script refreshes the SDK Manager entry of sources.json
    passthru = old.passthru or { } // {
      inherit (perSystem.self.connectiq-sdk) updateScript;
    };
  })
