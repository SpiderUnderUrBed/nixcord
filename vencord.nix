{ pkgs, buildNpmPackage, fetchgit, curl, esbuild, fetchFromGitHub, git, jq, lib, nix-update, nodejs, pnpm, stdenv, writeShellScript, buildWebExtension ? false }:

let
  version = "1.10.5";
  pname = "vencord";  # Define pname here

  repo = fetchFromGitHub {
    owner = "Vendicated";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-pzb2x5tTDT6yUNURbAok5eQWZHaxP/RUo8T0JECKHJ4=";
  };

  # Vendored node modules using buildNpmPackage
nodeModules = buildNpmPackage rec {
  inherit pname version;
  src = repo;
  inherit nodejs;

  # Use the lockfile if it’s available
  lockfile = "${src}/package-lock.json";  # Or "${src}/pnpm-lock.yaml" for pnpm

  # Optional: Fake hash to bypass online checking
  npmDepsHash = lib.fakeHash;

  # nativeBuildInputs = [
  #  # nodejs
  #   pkgs.pnpm  # Ensure pnpm is available
  # ];

  postPatch = ''
    # Generate lockfile offline
    if [ ! -f "${src}/package-lock.json" ]; then
      ${pkgs.pnpm}/bin/pnpm install --lockfile-only --offline
    fi
  '';
};


in
stdenv.mkDerivation {
  inherit pname version;

  outputs = [ "out" "api" "node_modules" ];

  src = repo;

  nativeBuildInputs = [
    git
    nodejs
    # Add nodeModules as a build input
    nodeModules
  ];

  env = {
    ESBUILD_BINARY_PATH = lib.getExe (
      esbuild.overrideAttrs (
        final: _: {
          version = "0.15.18";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${final.version}";
            hash = "sha256-b9R1ML+pgRg9j2yrkQmBulPuLHYLUQvW+WTyR/Cq6zE=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        }
      )
    );
    VENCORD_REMOTE = "${repo.owner}/${repo.repo}";
    VENCORD_HASH = "deadbeef";
  };

  buildPhase = ''
    api_path=$api
    node_module_path=${nodeModules}/node_modules

    mkdir -p "$api_path"
    mv src/api/* "$api_path/"
    rmdir src/api
    ln -sf "$api_path" src/api

    # Link the pre-fetched node_modules
    mkdir -p node_modules
    ln -sf "$node_module_path" node_modules

    runHook preBuild

    substituteInPlace ./scripts/build/common.mjs \
      --replace-warn 'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*"]' \
              'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*", "@api/*", "nanoid"]' \
      --replace-warn 'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin]' \
        'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin, { name: "api-alias-plugin", setup(build) { build.onResolve({ filter: /^@api\// }, async (args) => { const fs = await import("fs"); const path = await import("path"); let resolvedPath = args.path.replace(/^@api/, "'"$api_path"'"); const extensions = [".ts", ".tsx", ".js", ".jsx"]; for (const ext of extensions) { const testPath = path.resolve(resolvedPath + ext); if (fs.existsSync(testPath)) { return { path: testPath }; } } if (fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory()) { resolvedPath = path.join(resolvedPath, "index"); for (const ext of extensions) { const testPath = resolvedPath + ext; if (fs.existsSync(testPath)) { return { path: testPath }; } } } return { path: resolvedPath }; }); } }, { name: "nanoid-alias-plugin", setup(build) { build.onResolve({ filter: /^nanoid$/ }, (args) => { return { path: "$node_module_path/nanoid" }; }); } }]'  \

    pnpm run ${if buildWebExtension then "buildWeb" else "build"} \
     -- --standalone --disable-updater

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist/${lib.optionalString buildWebExtension "chromium-unpacked/"} $out
    runHook postInstall
  '';

  passthru.updateScript = writeShellScript "update-vencord" ''
    export PATH="${
      lib.makeBinPath [
        curl
        jq
        nix-update
      ]
    }:$PATH"
    ghTags=$(curl ''${GITHUB_TOKEN:+" -u \":$GITHUB_TOKEN\""} "https://api.github.com/repos/Vendicated/Vencord/tags")
    latestTag=$(echo "$ghTags" | jq -r .[0].name)

    echo "Latest tag: $latestTag"

    exec nix-update --version "$latestTag" "$@"
  '';

  meta = with lib; {
    description = "Vencord web extension";
    homepage = "https://github.com/Vendicated/Vencord";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [
      FlafyDev
      NotAShelf
      Scrumplex
    ];
  };
}
