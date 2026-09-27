{
  stdenv,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs,
  pnpm,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nixcon-2026-advanced-testing-slides";
  version = "0.1.0";

  src = ./slides;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 4;
    hash = "sha256-ShmyFUc5EuhyRknaKNJ6h8BcY6EE1teWH+BZJVYWwGs=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm exec slidev build --base "$SLIDEV_BASE" --out dist
    runHook postBuild
  '';

  SLIDEV_BASE = "/NixCon_2026_advanced_testing_slides/";

  installPhase = ''
    runHook preInstall
    cp -r dist "$out"
    runHook postInstall
  '';
})
