{
  description = "Garmin Connect IQ SDK and SDK Manager for Nix";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # Garmin only ships x86_64 Linux binaries.
      systems = [ "x86_64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f (pkgsFor system));

      unfreeNames = [
        "connectiq-sdk"
        "connectiq-sdk-manager"
      ];
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
          config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg) unfreeNames;
        };
    in
    {
      overlays.default = final: _prev: {
        connectiq-sdk = final.callPackage ./pkgs/connectiq-sdk { };
        connectiq-sdk-manager = final.callPackage ./pkgs/connectiq-sdk-manager { };
        connectiq-sdk-use = final.callPackage ./pkgs/connectiq-sdk-use { };
      };

      packages = forAllSystems (pkgs: {
        inherit (pkgs) connectiq-sdk connectiq-sdk-manager connectiq-sdk-use;
        default = pkgs.connectiq-sdk;

        update = pkgs.writeShellApplication {
          name = "update-connectiq-sources";
          runtimeInputs = [
            pkgs.python3
            pkgs.nix
          ];
          text = ''exec python3 ${./scripts/update.py} "$@"'';
        };

        # Used by CI and for manual checks of the GUIs; see tests/gui-screenshot.sh.
        gui-screenshot = pkgs.writeShellApplication {
          name = "connectiq-gui-screenshot";
          runtimeInputs = with pkgs; [
            coreutils
            dbus
            imagemagick
            tesseract
            xdotool
            xorg-server
          ];
          text = builtins.readFile ./tests/gui-screenshot.sh;
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe pkgs.connectiq-sdk-manager;
        };
        sdkmanager = self.apps.${pkgs.stdenv.hostPlatform.system}.default;
        update = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.update;
        };
      });

      devShells = forAllSystems (pkgs: {
        # Connect IQ development: SDK from Nix, devices from the SDK Manager.
        default = pkgs.mkShell {
          packages = [
            pkgs.connectiq-sdk
            pkgs.connectiq-sdk-manager
            pkgs.connectiq-sdk-use
          ];
          CONNECTIQ_SDK_HOME = "${pkgs.connectiq-sdk}/${pkgs.connectiq-sdk.sdkPath}";
          shellHook = ''
            connectiq-sdk-use >/dev/null
          '';
        };
      });

      checks = forAllSystems (pkgs: import ./tests { inherit pkgs; });

      templates.default = {
        path = ./templates/default;
        description = "Connect IQ app with the SDK from Nix and devices from the SDK Manager";
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
