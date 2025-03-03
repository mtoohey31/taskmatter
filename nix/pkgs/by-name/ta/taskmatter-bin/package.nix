{ fetchurl, stdenv }:

stdenv.mkDerivation {
  pname = "taskmatter";
  version = "2.0.0";

  src = fetchurl {
    url = "https://github.com/mtoohey31/taskmatter/releases/download/v2.0.0/taskmatter";
    hash = "sha256-5l872HZ412PIkubQr71FwaALHaPPNvAsGbg///OzXx0=";
  };

  phases = [ "installPhase" ];

  installPhase = ''
    install -D $src -T $out/bin/taskmatter
  '';
}
