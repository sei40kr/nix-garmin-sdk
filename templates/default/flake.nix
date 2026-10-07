{
  description = "Connect IQ app";

  inputs = {
    nixpkgs.follows = "garmin-sdk/nixpkgs";
    garmin-sdk.url = "github:sei40kr/nix-garmin-sdk";
  };

  outputs =
    { nixpkgs, garmin-sdk, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      ciq = garmin-sdk.packages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          ciq.connectiq-sdk # monkeyc, monkeydo, connectiq (simulator), ...
          ciq.connectiq-sdk-manager # sdkmanager: log in and download devices
          ciq.connectiq-sdk-use
        ];
        # Point ~/.Garmin/ConnectIQ/current-sdk.cfg at the SDK from Nix so that
        # editors (Monkey C extension) and the SDK Manager use it.
        shellHook = ''
          connectiq-sdk-use >/dev/null
        '';
      };
    };
}
