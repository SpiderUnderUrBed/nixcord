{
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
stdenv.mkDerivation (finalAttrs: {
  pname = "vencord";
  version = "1.10.5";
  
  outputs = ["out" "api"];

 # trace = import <nixpkgs> { }.trace;
  src = lib.debug.traceValFn (v: "Fetched source path: ${v.outPath}") (fetchFromGitHub {
    owner = "Vendicated";
    repo = "Vencord";
    rev = "v${finalAttrs.version}";
    hash = "sha256-pzb2x5tTDT6yUNURbAok5eQWZHaxP/RUo8T0JECKHJ4=";
  });
 # srcOutPath = src.outPath;

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
    # TODO: somehow update this automatically
    VENCORD_HASH = "deadbeef";
  };

  buildPhase = ''
    api_path="$(realpath "$api")"

    mkdir -p "$api_path"
    mv src/api/* "$api_path/"
    rmdir src/api
    ln -sf "$api_path" src/api

    substituteInPlace ./scripts/build/common.mjs \
  --replace 'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*"]' \
          'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*", "@api/*", "nanoid"]' \
  --replace 'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin]' \
          'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin, { name: "alias-plugin", setup: function(build) { build.onResolve({ filter: /^@api\\// }, function(args) { \
              const path = args.path.replace(/^@api/, "'"$api_path"'"); \
              const fs = require("fs"); \
              return new Promise((resolve, reject) => { \
                  fs.stat(path, (err, stats) => { \
                      if (!err) { \
                          if (stats.isDirectory()) { \
                              resolve({ path: path + "/index.ts" }); \
                          } else { \
                              resolve({ path: path }); \
                          } \
                      } else if (err.code === "ENOENT") { \
                          resolve({ path: path + ".tsx" }); \
                      } else { \
                          reject(err); \
                      } \
                  }); \
              }); \
          }); } }]'


    runHook preBuild

    pnpm run ${if buildWebExtension then "buildWeb" else "build"} \
     -- --standalone --disable-updater

    runHook postBuild
  '';

  installPhase = ''
    #cp -r ./ $out
    runHook preInstall

    cp -r dist/${lib.optionalString buildWebExtension "chromium-unpacked/"} $out

    runHook postInstall
  '';

  # fixupPhase = ''
  #     rm -rf $out/src
  #     mv $out/dist/* $out
  #     rm -rf $out/dist
  # '';

  # We need to fetch the latest *tag* ourselves, as nix-update can only fetch the latest *releases* from GitHub
  # Vencord had a single "devbuild" release that we do not care about
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
