{ pkgs, buildNpmPackage, fetchgit, curl, esbuild, fetchFromGitHub, git, jq, lib, nix-update, nodejs, pnpm, stdenv, writeShellScript, buildWebExtension ? false }:

let
  pname = "vencord";
  version = "1.10.5";
  owner = "Vendicated";
  repo = fetchFromGitHub {
      inherit owner;
      repo = pname;
      rev = "v${version}";
      hash = "sha256-pzb2x5tTDT6yUNURbAok5eQWZHaxP/RUo8T0JECKHJ4=";
  };
  pnpmDeps = pnpm.fetchDeps {
    pname = "${pname}";
    src = repo;
    hash = "sha256-YBWe4MEmFu8cksOIxuTK0deO7q0QuqgOUc9WkUNBwp0=";
  };
  pnpmToNPM = buildNpmPackage rec {
    pname = "pnpm-lock-to-npm-lock";
    version = "1.0.0";
    src = fetchFromGitHub {
      owner = "jakedoublev";
      repo = "pnpm-lock-to-npm-lock";
      rev = "va67f352";
    };
   # buildInputs = [ pkgs.makeWrapper ];
    # installPhase = ''
    # '';
  };
  npmDeps = buildNpmPackage rec {
    pname = "vencord-deps";
    version = "1.0.0";
    src = repo;
    nativeBuildInputs = [
     # pnpmToNPM  # pnpm-lock-to-npm-lock is now available in npmDeps environment
      nodejs
      pnpm
    ];
    postPatch = ''
     ${pnpmToNPM}/node_modules/pnpm-lock-to-npm-lock/bin/pnpm-lock-to-npm-lock pnpm-lock.yaml
    '';
  };
in
stdenv.mkDerivation {
  inherit pname version owner pnpmDeps;

  outputs = [ "out" "api" "node_modules" ];

  src = repo;

  nativeBuildInputs = [
    git
    nodejs
    pnpm.configHook
    pnpmDeps
    pnpmToNPM
  ];
  #++ (if builtins.hasAttr "pnpm" pkgs then [ pnpmDeps ] else []);

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
    VENCORD_REMOTE = "${owner}/${pname}";
    VENCORD_HASH = "deadbeef";
  };

  buildPhase = ''
    api_path=$api
    node_module_path=${npmDeps}/node_modules

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
        'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin, { name: "api-alias-plugin", setup(build) { build.onResolve({ filter: /^@api\// }, async (args) => { const fs = await import("fs"); const path = await import("path"); let resolvedPath = args.path.replace(/^@api/, "'"$api_path"'"); const extensions = [".ts", ".tsx", ".js", ".jsx"]; for (const ext of extensions) { const testPath = path.resolve(resolvedPath + ext); if (fs.existsSync(testPath)) { return { path: testPath }; } } if (fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory()) { resolvedPath = path.join(resolvedPath, "index"); for (const ext of extensions) { const testPath = resolvedPath + ext; if (fs.existsSync(testPath)) { return { path: testPath }; } } } return { path: resolvedPath }; }); } }, { name: "nanoid-alias-plugin", setup(build) { build.onResolve({ filter: /^nanoid$/ }, async (args) => { const path = await import("path"); return { path: path.resolve("'"$node_module_path"'", "nanoid") }; }); } }]'  \

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
    ghTags=$(curl ''${GITHUB_TOKEN:+" -u \":$GITHUB_TOKEN\""} "https://api.github.com/repos/${owner}/${pname}/tags")
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
