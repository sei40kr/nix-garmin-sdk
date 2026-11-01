{ pkgs, perSystem, ... }:
(pkgs.callPackage ./package.nix {
  source = (pkgs.lib.importJSON ../../sources.json).sdkManager;
}).overrideAttrs
  (old: {
    # The same script refreshes the SDK Manager entry of sources.json
    passthru = old.passthru or { } // {
      inherit (perSystem.self.connectiq-sdk) updateScript;
    };
  })
