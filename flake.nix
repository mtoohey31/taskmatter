{
  description = "taskmatter";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "utils";
        systems.follows = "utils/systems";
      };
    };
  };

  outputs = { self, nixpkgs, utils, poetry2nix }: {
    overlays = rec {
      expects-poetry2nix = final: prev: {
        taskmatter = final.poetry2nix.mkPoetryApplication {
          projectDir = ./.;
          overrides = final.poetry2nix.overrides.withDefaults (_: prev: {
            monthdelta = prev.monthdelta.overridePythonAttrs (oldAttrs: {
              propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [
                prev.setuptools
              ];
            });
          });
        };
      };

      default = _: prev: {
        inherit (prev.appendOverlays [
          poetry2nix.overlays.default
          expects-poetry2nix
        ]) taskmatter;
      };
    };
  } // utils.lib.eachDefaultSystem (system: with import nixpkgs
    { overlays = [ self.overlays.default ]; inherit system; }; {
    packages.default = taskmatter;

    devShells.default = taskmatter.dependencyEnv.overrideAttrs (oldAttrs: {
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
        poetry
        python3
        python3Packages.python-lsp-server
      ];
    });
  });
}
