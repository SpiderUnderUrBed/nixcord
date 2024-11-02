{
 # buildNpmPackage,
  #fetchgit,
  pkgs,
  curl,
  esbuild,
  fetchFromGitHub,
  git,
  jq,
  lib,
  nix-update,
  nodejs,
  pnpm,
  stdenv,
  writeShellScript,
  buildWebExtension ? false,
}:
let
  version = "1.10.5";
  repo = fetchFromGitHub {
    owner = "Vendicated";
    repo = "Vencord";
    rev = "v${version}";
    hash = "sha256-pzb2x5tTDT6yUNURbAok5eQWZHaxP/RUo8T0JECKHJ4=";
  };
  nodeDeps = pkgs.runCommand "nodeDeps" {
    buildInputs = [ pkgs.nodePackages.node2nix ];
  } ''
    mkdir -p $out
    cp ${repo}/package.json $out
    cd $out
    node2nix -i package.json -o node-packages.nix
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "vencord";
  version = version;

  outputs = ["out" "api"];

  src = repo;

  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname src;
    hash = "sha256-YBWe4MEmFu8cksOIxuTK0deO7q0QuqgOUc9WkUNBwp0=";
  };

  nativeBuildInputs = [
    git
    nodejs
    pnpm.configHook
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
    VENCORD_REMOTE = "${finalAttrs.src.owner}/${finalAttrs.src.repo}";
    VENCORD_HASH = "deadbeef";
  };

  buildPhase = ''
    api_path=$api

    mkdir -p "$api_path"
    mv src/api/* "$api_path/"
    rmdir src/api
    ln -sf "$api_path" src/api
    
    runHook preBuild

    substituteInPlace ./scripts/build/common.mjs \
      --replace-warn 'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*"]' \
              'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*", "@api/*", "${(pkgs.callPackage "${nodeDeps}/default.nix" {}).nodeDependencies}/lib/node_modules/nanoid"]' \
      --replace-warn 'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin]' \
        'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin, { name: "alias-plugin", setup(build) { build.onResolve({ filter: /^@api\// }, async (args) => { const fs = await import("fs"); const path = await import("path"); let resolvedPath = args.path.replace(/^@api/, "'"$api_path"'"); const extensions = [".ts", ".tsx", ".js", ".jsx"]; for (const ext of extensions) { const testPath = path.resolve(resolvedPath + ext); if (fs.existsSync(testPath)) { return { path: testPath }; } } if (fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory()) { resolvedPath = path.join(resolvedPath, "index"); for (const ext of extensions) { const testPath = resolvedPath + ext; if (fs.existsSync(testPath)) { return { path: testPath }; } } } return { path: resolvedPath }; }); } }]' \
    #  --replace-warn 'esbuild.build({' \
    #         'esbuild.build({ resolveExtensions: [".ts", ".tsx", ".js", ".jsx"],'

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
})
