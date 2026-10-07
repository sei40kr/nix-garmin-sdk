# glib-networking built with the OpenSSL TLS backend instead of GnuTLS.
#
# Nixpkgs' GnuTLS only trusts /etc/ssl/certs/ca-certificates.crt and offers no
# environment override, so WebKit fails with TLS errors on distributions that
# ship the CA bundle elsewhere (e.g. Fedora). OpenSSL from Nixpkgs honours
# SSL_CERT_FILE and NIX_SSL_CERT_FILE, which the wrappers can point at the
# right bundle.
{
  glib-networking,
  openssl,
}:

glib-networking.overrideAttrs (old: {
  pname = "glib-networking-openssl";
  outputs = [ "out" ];
  buildInputs = old.buildInputs ++ [ openssl ];
  mesonFlags = [
    "-Dgnutls=disabled"
    "-Dopenssl=enabled"
    "-Dinstalled_tests=false"
  ];
  postFixup = "";
  passthru = { };
})
