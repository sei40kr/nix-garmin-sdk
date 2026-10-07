{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeShellWrapper,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  source ? (import ../sources.nix { inherit lib; }).sdkManager,
}:

let
  common = callPackage ../common.nix { };
in
stdenv.mkDerivation {
  pname = "connectiq-sdk-manager";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = "sdkmanager";
  unpackPhase = ''
    runHook preUnpack
    mkdir sdkmanager
    unzip -q "$src" -d sdkmanager
    runHook postUnpack
  '';

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeShellWrapper
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = common.runtimeLibs ++ common.gappsInputs;

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  # The wrapper needs --run, which only shell wrappers support.
  dontWrapGApps = true;

  # wxWidgets resolves its resources as <prefix>/share/sdkmanager, where
  # <prefix> is the parent of the executable's directory.
  installPhase = ''
    runHook preInstall

    install -Dm755 bin/sdkmanager $out/bin/sdkmanager
    mkdir -p $out/share
    cp -r share/sdkmanager $out/share/
    install -Dm644 share/sdkmanager/connectiq-icon.png \
      $out/share/icons/hicolor/256x256/apps/connectiq-sdk-manager.png

    ${common.retargetWebkit "$out/bin/sdkmanager"}
    ${common.hideEmbeddedLibs "$out/bin/sdkmanager"}

    runHook postInstall
  '';

  postFixup = ''
    wrapProgramShell $out/bin/sdkmanager "''${gappsWrapperArgs[@]}" ${lib.escapeShellArgs common.wrapperArgs}
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "connectiq-sdk-manager";
      desktopName = "Connect IQ SDK Manager";
      comment = "Download Connect IQ device definitions and SDKs";
      exec = "sdkmanager";
      icon = "connectiq-sdk-manager";
      categories = [ "Development" ];
    })
  ];

  meta = common.meta // {
    description = "Garmin Connect IQ SDK Manager (downloads device definitions and SDKs)";
    homepage = "https://developer.garmin.com/connect-iq/sdk/";
    license = {
      fullName = "Connect IQ SDK License Agreement";
      url = "https://developer.garmin.com/connect-iq/sdk/";
      free = false;
    };
    mainProgram = "sdkmanager";
  };
}
