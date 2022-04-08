{
  description = "Taskmatter";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    {
      overlay = nixpkgs.lib.composeManyExtensions [
        poetry2nix.overlay
        (self: super: {
          taskmatter = super.poetry2nix.mkPoetryApplication { projectDir = ./.; };
        })
      ];
    } // flake-utils.lib.eachDefaultSystem (system: {
      defaultPackage = (import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      }).taskmatter;
    });
}
