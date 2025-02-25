{
  description = "taskmatter";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: {
    overlays = {
      default = final: _: {
        taskmatter =
          final.callPackage ./pkgs/by-name/ta/taskmatter/package.nix { };
      };
    };
  } // flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        overlays = [ self.overlays.default ];
        inherit system;
      };
      inherit (pkgs) mkShell sourcekit-lsp swift swiftPackages swiftpm2nix
        swift-format taskmatter;
    in
    {
      packages.default = taskmatter;

      devShells.default = (mkShell.override { inherit (swift) stdenv; }) {
        packages = [ sourcekit-lsp swift swiftpm2nix swift-format ];
        LD_LIBRARY_PATH = "${swiftPackages.Dispatch}/lib";
      };
    });
}

