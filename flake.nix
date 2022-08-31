{
  description = "taskmatter";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }: {
    overlays.default = final: prev: {
      taskmatter = final.poetry2nix.mkPoetryApplication {
        projectDir = ./.;
      };
    };
  } // utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        overlays = [ self.overlays.default ];
        inherit system;
      };
    in
    with pkgs; {
      packages.default = taskmatter;

      devShells.default = (pkgs.poetry2nix.mkPoetryEnv {
        projectDir = ./.;
      }).overrideAttrs (oldAttrs: {
        nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
          poetry
          python3
          python3Packages.python-lsp-server
        ];
      });
    });
}
