{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  wrapGAppsHook3,
  coreutils,
  findutils,
  jre,
  at-spi2-core,
  cairo,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  glib-networking,
  gtk3,
  libjpeg8,
  libpng,
  libsecret,
  libsm,
  libusb1,
  libx11,
  libxext,
  libxkbcommon,
  libxxf86vm,
  pango,
  systemdLibs,
  webkitgtk_4_1,
  zlib,
  source,
}:

let
  tools = [
    "barrelbuild"
    "barreltest"
    "connectiq"
    "era"
    "mdd"
    "monkeyc"
    "monkeydo"
    "monkeydoc"
    "monkeygraph"
    "monkeym"
    "monkeymotion"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "connectiq-sdk";
  inherit (source) version;

  src = fetchurl {
    url = "https://developer.garmin.com/downloads/connect-iq/sdks/${source.file}";
    inherit (source) hash;
  };

  # The archive has no top-level directory
  unpackCmd = "unzip -q $curSrc -d sdk";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    wrapGAppsHook3
  ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    at-spi2-core
    cairo
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    glib-networking
    gtk3
    libjpeg8
    libpng
    libsecret
    libsm
    libusb1
    libx11
    libxext
    libxkbcommon
    libxxf86vm
    pango
    systemdLibs
    webkitgtk_4_1
    zlib
  ];

  dontBuild = true;
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    rm bin/*.bat
    # Some launchers (e.g. monkeym) are shipped without the executable bit
    chmod +x ${lib.concatMapStringsSep " " (tool: "bin/${tool}") tools}

    # The GUIs look up their resources in ../share/<name> relative to the binary
    mkdir -p $out/share/connectiq-sdk $out/bin $out/libexec
    cp -r . $out/share/connectiq-sdk

    substitute ${./launcher.sh} $out/libexec/connectiq-sdk-launcher \
      --subst-var-by runtimeShell ${stdenv.shell} \
      --subst-var-by sdk $out/share/connectiq-sdk \
      --subst-var-by name "$(basename $out)" \
      --subst-var-by binPath ${
        lib.makeBinPath [
          coreutils
          findutils
          jre
        ]
      }
    chmod +x $out/libexec/connectiq-sdk-launcher
    for tool in ${lib.concatStringsSep " " tools}; do
      ln -s ../libexec/connectiq-sdk-launcher $out/bin/$tool
    done

    runHook postInstall
  '';

  preFixup = ''
    # Before autoPatchelfHook, so it resolves the 4.1 names (see README)
    patchelf \
      --replace-needed libwebkit2gtk-4.0.so.37 libwebkit2gtk-4.1.so.0 \
      --replace-needed libjavascriptcoregtk-4.0.so.18 libjavascriptcoregtk-4.1.so.0 \
      --remove-needed libsoup-2.4.so.1 \
      $out/share/connectiq-sdk/bin/simulator $out/share/connectiq-sdk/bin/monkeymotion

    wrapGApp $out/share/connectiq-sdk/bin/simulator
    wrapGApp $out/share/connectiq-sdk/bin/monkeymotion
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME="$(mktemp -d)" $out/bin/monkeyc --version | grep -F "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Garmin Connect IQ SDK for building apps for Garmin wearables";
    longDescription = ''
      The Garmin Connect IQ SDK, including the Monkey C compiler (monkeyc)
      and the simulator (connectiq). Device files still have to be
      downloaded with the Connect IQ SDK Manager into
      ~/.Garmin/ConnectIQ/Devices. The Java tools run from a per-user copy
      of the SDK under ~/.cache/connectiq-sdk, where monkeyc can write
      default.jungle.
    '';
    homepage = "https://developer.garmin.com/connect-iq/sdk/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    maintainers = with lib.maintainers; [ sei40kr ];
    mainProgram = "monkeyc";
    platforms = [ "x86_64-linux" ];
  };
})
