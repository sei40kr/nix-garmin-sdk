{
  description = "Garmin Connect IQ SDKs and SDK Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      outputs = inputs.blueprint {
        inherit inputs;
        systems = [ "x86_64-linux" ];
        nixpkgs.config.allowUnfree = true;
      };
    in
    outputs
    // {
      # blueprint maps one file to one package, so the versioned SDKs listed in
      # sources.json are exposed through connectiq-sdk instead
      packages = builtins.mapAttrs (
        _: packages: packages // packages.connectiq-sdk.versions
      ) outputs.packages;
    };
}
