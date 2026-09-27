{
  description = "NixCon 2026 talk: Advanced NixOS Integration Test Scenarios";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        slides = pkgs.callPackage ./package.nix { };
      in
      {
        packages.slides = slides;
        packages.default = slides;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs
            pkgs.pnpm
            pkgs.d2
          ];
        };
      }
    );
}
