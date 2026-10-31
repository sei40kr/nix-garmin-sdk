{
  runCommand,
  libsoup_3,
  webkitgtk_4_1,
}:

# The SDK Manager and the SDK GUIs link against webkit2gtk-4.0 and
# libsoup-2.4, which nixpkgs dropped. None of them call libsoup directly,
# and every webkit/JSC symbol they use exists in 4.1, so webkit2gtk-4.1 (on
# libsoup-3) is a drop-in replacement.
runCommand "webkitgtk-4.0-compat" { } ''
  mkdir -p $out/lib
  ln -s ${webkitgtk_4_1}/lib/libwebkit2gtk-4.1.so.0 $out/lib/libwebkit2gtk-4.0.so.37
  ln -s ${webkitgtk_4_1}/lib/libjavascriptcoregtk-4.1.so.0 $out/lib/libjavascriptcoregtk-4.0.so.18
  ln -s ${libsoup_3}/lib/libsoup-3.0.so.0 $out/lib/libsoup-2.4.so.1
''
