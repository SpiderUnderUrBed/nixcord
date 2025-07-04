# Made from nixpkgs pkg and updated with nix-update
# identical to nixpkgs source, but maintained here for
# quicker updates that don't wait on hydra

{
  esbuild,
  fetchFromGitHub,
  gitMinimal,
  lib,
  nodejs_22,
  stdenv,
  buildWebExtension ? false,
  unstable ? false,
  pnpm_10,
}:

let
  stableVersion = "1.12.5";
  stableHash = "sha256-RAYU6ZMnbLBtWI11JqLI+/8+PM2UqRxadpne2s9nmSA=";
  stablePnpmDeps = "sha256-hO6QKRr4jTfesRDAEGcpFeJmGTGLGMw6EgIvD23DNzw=";

  unstableVersion = "1.12.5-unstable-2025-07-04";
  unstableRev = "643122e323fd9b36b456b42ef13e159f5b10015e";
  unstableHash = "sha256-ojy4cRT4Nef8HF+uwxwjbrE210Dkq5yjqmk4tygiNKE=";
  unstablePnpmDeps = "sha256-hO6QKRr4jTfesRDAEGcpFeJmGTGLGMw6EgIvD23DNzw=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "vencord" + lib.optionalString unstable "-unstable";
  version = if unstable then unstableVersion else stableVersion;

  src = fetchFromGitHub {
    owner = "Vendicated";
    repo = "Vencord";
    rev = if unstable then unstableRev else "v${finalAttrs.version}";
    hash = if unstable then unstableHash else stableHash;
  };

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname src;
    hash = if unstable then unstablePnpmDeps else stablePnpmDeps;
  };

  nativeBuildInputs = [
    gitMinimal
    nodejs_22
    pnpm_10.configHook
  ];

  env = {
    ESBUILD_BINARY_PATH = lib.getExe (
      esbuild.overrideAttrs (
        final: _: {
          version = "0.25.1";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${final.version}";
            hash = "sha256-vrhtdrvrcC3dQoJM6hWq6wrGJLSiVww/CNPlL1N5kQ8=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        }
      )
    );
    VENCORD_REMOTE = "${finalAttrs.src.owner}/${finalAttrs.src.repo}";
    VENCORD_HASH = "${finalAttrs.version}";
  };

  buildPhase = ''
    runHook preBuild
    pnpm run ${if buildWebExtension then "buildWeb" else "build"} \
      -- --standalone --disable-updater
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist/${lib.optionalString buildWebExtension "chromium-unpacked/"} "$out"
    cp package.json "$out"
    runHook postInstall
  '';

  meta = {
    description = "Vencord web extension" + lib.optionalString unstable " (Unstable)";
    homepage = "https://github.com/Vendicated/Vencord";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [
      donteatoreo
      FlafyDev
      NotAShelf
      Scrumplex
    ];
  };
})
