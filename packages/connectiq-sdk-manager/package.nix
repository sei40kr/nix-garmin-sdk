{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  curl,
  expat,
  fontconfig,
  freetype,
  glib,
  glib-networking,
  gtk3,
  libjpeg8,
  libpng,
  libsecret,
  libsm,
  libx11,
  libxext,
  libxkbcommon,
  libxxf86vm,
  webkitgtk_4_0-compat,
  webkitgtk_4_1,
  zlib,
  source,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "connectiq-sdk-manager";
  inherit (source) version;

  # Upstream only publishes the latest release under an unversioned URL
  src = fetchurl {
    url = "https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-linux.zip";
    inherit (source) hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    curl
    expat
    fontconfig
    freetype
    glib
    # The login page needs TLS through GIO
    glib-networking
    gtk3
    libjpeg8
    libpng
    libsecret
    libsm
    libx11
    libxext
    libxkbcommon
    libxxf86vm
    webkitgtk_4_0-compat
    webkitgtk_4_1
    zlib
  ];

  dontBuild = true;
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    # Resources are looked up in ../share/sdkmanager relative to the binary
    mkdir -p $out
    cp -r bin share $out
    install -Dm444 share/sdkmanager/connectiq-icon.png \
      $out/share/pixmaps/connectiq-sdk-manager.png

    runHook postInstall
  '';

  preFixup = ''
    wrapGApp $out/bin/sdkmanager
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "connectiq-sdk-manager";
      desktopName = "Connect IQ SDK Manager";
      comment = finalAttrs.meta.description;
      exec = "sdkmanager";
      icon = "connectiq-sdk-manager";
      categories = [ "Development" ];
    })
  ];

  meta = {
    description = "Garmin tool to download Connect IQ device files and SDKs";
    longDescription = ''
      Downloads Connect IQ device files and fonts into ~/.Garmin/ConnectIQ,
      which the connectiq-sdk packages of this flake pick up. SDKs it
      downloads contain unpatched binaries and do not run on NixOS; use the
      connectiq-sdk packages instead.
    '';
    homepage = "https://developer.garmin.com/connect-iq/sdk/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ sei40kr ];
    mainProgram = "sdkmanager";
    platforms = [ "x86_64-linux" ];
  };
})
