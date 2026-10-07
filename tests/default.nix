# Offline smoke tests, run by `nix flake check`.
{ pkgs }:

let
  inherit (pkgs)
    lib
    runCommand
    connectiq-sdk
    connectiq-sdk-manager
    connectiq-sdk-use
    ;
  common = pkgs.callPackage ../pkgs/common.nix { };

  guiTestInputs = [
    pkgs.xvfb-run
    pkgs.procps
    pkgs.coreutils
  ];

  # Starts a GUI program on a virtual display and fails if it dies within the
  # grace period or logs a dynamic-linking or libsoup ABI problem.
  guiSmokeTest =
    name: command:
    runCommand name { nativeBuildInputs = guiTestInputs; } ''
      export HOME=$TMPDIR/home
      mkdir -p $HOME
      log=$TMPDIR/${name}.log
      xvfb-run -a -s "-screen 0 1280x800x24" \
        timeout --preserve-status -s TERM 20 ${command} >$log 2>&1 && status=0 || status=$?
      cat $log
      # 143 = killed by SIGTERM from timeout, i.e. it was still running.
      if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then
        echo "${name}: exited early with status $status" >&2
        exit 1
      fi
      if grep -E "error while loading shared libraries|symbol lookup error|undefined symbol|libsoup2 symbols|Using libsoup2 and libsoup3" $log; then
        echo "${name}: runtime linking problem" >&2
        exit 1
      fi
      touch $out
    '';
in
{
  inherit connectiq-sdk connectiq-sdk-manager connectiq-sdk-use;

  sdk-cli = runCommand "connectiq-sdk-cli-test" { } ''
    export HOME=$TMPDIR
    ${lib.getExe connectiq-sdk} --version | tee $TMPDIR/version
    grep -q "Connect IQ Compiler version: ${connectiq-sdk.version}" $TMPDIR/version
    ${connectiq-sdk}/bin/monkeydoc --help >/dev/null 2>&1 || true
    touch $out
  '';

  sdk-use = runCommand "connectiq-sdk-use-test" { } ''
    export HOME=$TMPDIR
    sdk=${connectiq-sdk}/${connectiq-sdk.sdkPath}
    mkdir -p $HOME/.Garmin/ConnectIQ
    printf 'foo=bar\ncurrent-sdk=/old/\n[Section]\nx=y\n' > $HOME/.Garmin/ConnectIQ/sdkmanager-config.ini
    ${lib.getExe connectiq-sdk-use}
    [ "$(cat $HOME/.Garmin/ConnectIQ/current-sdk.cfg)" = "$sdk/" ]
    diff -u <(printf 'foo=bar\ncurrent-sdk=%s/\n[Section]\nx=y\n' "$sdk") $HOME/.Garmin/ConnectIQ/sdkmanager-config.ini
    [ -d $HOME/.Garmin/ConnectIQ/Devices ]
    touch $out
  '';

  # The TLS backend WebKit and the wrappers rely on: a GIO TLS handshake against
  # a local server whose CA is only reachable through SSL_CERT_FILE.
  tls-backend =
    runCommand "connectiq-tls-backend-test"
      {
        nativeBuildInputs = [
          pkgs.openssl
          (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
          pkgs.gobject-introspection
        ];
        buildInputs = [ pkgs.glib ];
      }
      ''
        cd $TMPDIR
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Test CA" \
          -keyout ca.key -out ca.pem 2>/dev/null
        openssl req -newkey rsa:2048 -nodes -subj /CN=localhost \
          -keyout key.pem -out req.pem 2>/dev/null
        printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > ext.cnf
        openssl x509 -req -in req.pem -CA ca.pem -CAkey ca.key -CAcreateserial -days 1 \
          -extfile ext.cnf -out cert.pem 2>/dev/null
        openssl s_server -quiet -accept 127.0.0.1:8443 -cert cert.pem -key key.pem -www &
        server=$!
        sleep 1
        export GIO_EXTRA_MODULES=${common.glib-networking-openssl}/lib/gio/modules
        export GIO_USE_TLS=openssl
        export HOME=$TMPDIR
        # The sandbox sets NIX_SSL_CERT_FILE to a missing file, which OpenSSL
        # would prefer over SSL_CERT_FILE without the wrappers' CA setup.
        export SSL_CERT_FILE=$PWD/ca.pem
        . ${common.caSetup}
        python3 ${./tls-client.py} localhost 8443
        # And it must reject the server when the CA is not trusted.
        export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        . ${common.caSetup}
        if python3 ${./tls-client.py} localhost 8443; then
          echo "untrusted certificate was accepted" >&2
          exit 1
        fi
        kill $server
        touch $out
      '';

  # CA bundle selection done by the wrappers.
  ca-setup = runCommand "connectiq-ca-setup-test" { } ''
    cacert=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    touch $TMPDIR/a.crt $TMPDIR/b.crt
    check() {
      [ "$SSL_CERT_FILE" = "$1" ] && [ "$NIX_SSL_CERT_FILE" = "$1" ] || {
        echo "expected $1, got SSL_CERT_FILE=$SSL_CERT_FILE NIX_SSL_CERT_FILE=$NIX_SSL_CERT_FILE" >&2
        exit 1
      }
    }

    # Nothing usable (the sandbox has no /etc/ssl): fall back to cacert.
    unset SSL_CERT_FILE; export NIX_SSL_CERT_FILE=/no-cert-file.crt
    . ${common.caSetup}; check $cacert

    unset SSL_CERT_FILE; export NIX_SSL_CERT_FILE=$TMPDIR/a.crt
    . ${common.caSetup}; check $TMPDIR/a.crt

    export SSL_CERT_FILE=$TMPDIR/b.crt NIX_SSL_CERT_FILE=$TMPDIR/a.crt
    . ${common.caSetup}; check $TMPDIR/b.crt

    export SSL_CERT_FILE=/missing.crt NIX_SSL_CERT_FILE=$TMPDIR/a.crt
    . ${common.caSetup}; check $TMPDIR/a.crt
    touch $out
  '';

  sdk-simulator = guiSmokeTest "connectiq-simulator" "${connectiq-sdk}/bin/simulator";
  sdk-manager-gui = guiSmokeTest "connectiq-sdk-manager" (lib.getExe connectiq-sdk-manager);
}
