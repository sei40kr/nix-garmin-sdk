# Pieces shared by the SDK (simulator) and the SDK Manager. Both are wxGTK
# programs linked against the libsoup2-based WebKitGTK 4.0 ABI, which Nixpkgs no
# longer ships.
{
  lib,
  writeText,
  cacert,
  callPackage,
  atk,
  cairo,
  curl,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  gst_all_1,
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
  python3,
  stdenv,
  systemdLibs,
  webkitgtk_4_1,
  zlib,
}:

let
  glib-networking-openssl = callPackage ./glib-networking-openssl { };

  # Pick one readable CA bundle for OpenSSL (used by libcurl and, through
  # glib-networking, by WebKit) and export it under both variables: Nixpkgs'
  # OpenSSL prefers NIX_SSL_CERT_FILE over SSL_CERT_FILE, and either may point
  # to a missing file. An explicit SSL_CERT_FILE wins.
  caSetup = writeText "connectiq-ca-setup.sh" ''
    for f in "''${SSL_CERT_FILE:-}" \
             "''${NIX_SSL_CERT_FILE:-}" \
             /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt \
             /etc/ssl/ca-bundle.pem \
             /etc/ssl/cert.pem \
             ${cacert}/etc/ssl/certs/ca-bundle.crt; do
      if [ -n "$f" ] && [ -r "$f" ]; then
        export SSL_CERT_FILE="$f" NIX_SSL_CERT_FILE="$f"
        break
      fi
    done
  '';
in
{
  inherit glib-networking-openssl caSetup;

  # Libraries for autoPatchelfHook.
  runtimeLibs = [
    atk
    cairo
    curl
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
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
    stdenv.cc.cc.lib
    systemdLibs
    webkitgtk_4_1
    zlib
  ];

  # Extra buildInputs so that wrapGAppsHook3 picks up schemas and GIO modules.
  gappsInputs = [
    gsettings-desktop-schemas
    gtk3
    # WebKit needs appsink & co. even for pages without media.
    gst_all_1.gst-plugins-base
  ];

  # Retarget an ELF from the WebKitGTK 4.0 ABI to 4.1. The binaries never call
  # libsoup directly (no soup_* imports), so dropping libsoup2 is safe, and
  # every webkit_*/JS* symbol they import exists unchanged in the 4.1 ABI.
  # Loading libsoup2 next to the libsoup3 used by WebKitGTK 4.1 would abort.
  retargetWebkit = file: ''
    patchelf \
      --replace-needed libwebkit2gtk-4.0.so.37 libwebkit2gtk-4.1.so.0 \
      --replace-needed libjavascriptcoregtk-4.0.so.18 libjavascriptcoregtk-4.1.so.0 \
      --remove-needed libsoup-2.4.so.1 \
      ${file}
  '';

  # Hide the FreeType, libpng and libjpeg copies embedded in an executable from
  # the shared libraries it loads; see localize-dynsym.py.
  hideEmbeddedLibs = file: ''
    ${python3.interpreter} ${./localize-dynsym.py} ${file} '^(FT_|TT_|png_|jpeg_)'
  '';

  wrapperArgs = [
    "--prefix"
    "GIO_EXTRA_MODULES"
    ":"
    "${glib-networking-openssl}/lib/gio/modules"
    "--set"
    "GIO_USE_TLS"
    "openssl"
    # Blank or crashing web views on some GPU drivers otherwise.
    "--set-default"
    "WEBKIT_DISABLE_DMABUF_RENDERER"
    "1"
    "--run"
    ". ${caSetup}"
  ];

  meta = {
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
