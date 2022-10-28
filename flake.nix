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
        overrides = final.poetry2nix.overrides.withDefaults (_: prev: {
          monthdelta = prev.monthdelta.overridePythonAttrs (oldAttrs: {
            propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [
              prev.setuptools
            ];
          });
        });
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
