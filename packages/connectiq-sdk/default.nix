{ pkgs, ... }:
let
  inherit (pkgs) lib;
  sources = lib.importJSON ../../sources.json;
  webkitgtk_4_0-compat = pkgs.callPackage ./webkitgtk-4.0-compat.nix { };

  attrName =
    version: "connectiq-sdk_${lib.replaceStrings [ "." ] [ "_" ] (lib.versions.majorMinor version)}";
  versions = lib.listToAttrs (
    map (
      source:
      lib.nameValuePair (attrName source.version) (
        pkgs.callPackage ./package.nix { inherit source webkitgtk_4_0-compat; }
      )
    ) sources.sdks
  );
  latest = lib.last (lib.sort (a: b: lib.versionOlder a.version b.version) sources.sdks);
in
versions.${attrName latest.version}.overrideAttrs (old: {
  passthru = old.passthru or { } // {
    inherit versions webkitgtk_4_0-compat;
    updateScript = pkgs.writeShellApplication {
      name = "connectiq-sdk-update";
      runtimeInputs = with pkgs; [
        curl
        git
        jq
      ];
      text = builtins.readFile ../update.sh;
    };
  };
})
