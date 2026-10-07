{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeShellWrapper,
  wrapGAppsHook3,
  jdk17,
  python3,
  source ?
    let
      sources = import ../sources.nix { inherit lib; };
    in
    sources.sdks.${sources.latestMajor},
}:

let
  common = callPackage ../common.nix { };
  jdk = jdk17;
  # ELF executables that link GTK/WebKit and need the GApps wrapper.
  guiBinaries = [
    "simulator"
    "monkeymotion"
  ];
  # User-facing commands exposed in $out/bin.
  commands = [
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
    "shell"
    "simulator"
  ];
in
stdenv.mkDerivation {
  pname = "connectiq-sdk";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = "sdk";
  unpackPhase = ''
    runHook preUnpack
    mkdir sdk
    unzip -q "$src" -d sdk
    runHook postUnpack
  '';

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeShellWrapper
    wrapGAppsHook3
  ];

  buildInputs = common.runtimeLibs ++ common.gappsInputs ++ [ python3 ];

  dontConfigure = true;
  dontBuild = true;
  # Wrapped by hand: the binaries live outside $out/bin and need --run, which
  # only shell wrappers support.
  dontWrapGApps = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    sdk=$out/share/connectiq-sdk
    mkdir -p $sdk $out/bin
    cp -r . $sdk

    # The SDK Manager is packaged on its own (connectiq-sdk-manager).
    rm -f $sdk/bin/sdkmanager $sdk/bin/*.bat
    # monkeygraph ships with CRLF line endings, which breaks its shebang.
    sed -i 's/\r$//' $sdk/bin/monkeygraph
    # Not every launcher is marked executable in the archive.
    for c in ${lib.concatStringsSep " " commands} generateOptimizedYUV.py; do
      [ -e $sdk/bin/$c ] && chmod +x $sdk/bin/$c
    done

    for b in ${lib.concatStringsSep " " guiBinaries}; do
      ${common.retargetWebkit "$sdk/bin/$b"}
      ${common.hideEmbeddedLibs "$sdk/bin/$b"}
    done

    runHook postInstall
  '';

  postFixup = ''
    sdk=$out/share/connectiq-sdk

    # Wrap in place: the scripts locate their siblings via `dirname "$0"`.
    for b in ${lib.concatStringsSep " " guiBinaries}; do
      wrapProgramShell $sdk/bin/$b "''${gappsWrapperArgs[@]}" ${lib.escapeShellArgs common.wrapperArgs}
    done

    for c in ${lib.concatStringsSep " " commands}; do
      if [ -e $sdk/bin/$c ]; then
        makeShellWrapper $sdk/bin/$c $out/bin/$c \
          --prefix PATH : ${lib.makeBinPath [ jdk ]} \
          --set-default JAVA_HOME ${jdk.home}
      fi
    done
  '';

  passthru = {
    inherit jdk;
    # Absolute path of the SDK root, as expected by current-sdk.cfg and editors.
    sdkPath = "share/connectiq-sdk";
  };

  meta = common.meta // {
    description = "Garmin Connect IQ SDK (monkeyc compiler, simulator and tools)";
    homepage = "https://developer.garmin.com/connect-iq/sdk/";
    license = {
      fullName = "Connect IQ SDK License Agreement";
      url = "https://developer.garmin.com/connect-iq/sdk/";
      free = false;
    };
    mainProgram = "monkeyc";
  };
}
