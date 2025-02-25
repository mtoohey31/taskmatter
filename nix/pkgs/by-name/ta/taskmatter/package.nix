{ swift, swiftPackages, swiftpm, swiftpm2nix }:

swift.stdenv.mkDerivation {
  pname = "taskmatter";
  version = "0.1.0";

  src = builtins.path { path = ../../../../..; name = "taskmatter-src"; };

  nativeBuildInputs = [ swift swiftpm ];

  LD_LIBRARY_PATH = "${swiftPackages.Dispatch}/lib";

  configurePhase = (swiftpm2nix.helpers ./nix).configure;

  installPhase = ''
    install -D "$(swiftpmBinPath)/taskmatter" -t $out/bin
  '';

  # Need Swift 6.0 to be able to build this properly:
  # https://github.com/NixOS/nixpkgs/issues/343210
  meta.broken = true;
}
