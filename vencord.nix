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
  # pnpmToNpmRepo = pkgs.fetchFromGitHub {
  #     owner = "jakedoublev";
  #     repo = "pnpm-lock-to-npm-lock";
  #     rev = "a67f35286dfd6feba64a010e1b1005b6aa220e86";
  #     sha256 = "sha256-dO1hAQduC7nyoVqWOVdc/OSfUf7atmA+zcuQhmmTmBM=";
  # };

  # Fetch and cache dependencies using pnpm
  # joinedDeps = pkgs.symlinkJoin {
  #   name = "vencord-merged-deps";
  #   paths = [ repo pnpmDeps ];
  # };
  # Build the `pnpm-lock-to-npm-lock` tool without requiring network access
  # pnpmLockToNpmLock = pkgs.stdenv.mkDerivation rec {
  #   pname = "pnpm-lock-to-npm-lock";
  #   version = "1.0.0";

  #   src = pnpmToNpmRepo;

  #   pnpmDeps = pnpm.fetchDeps {
  #     inherit pname;
  #     src = pnpmToNpmRepo;
  #     hash = "sha256-iK0FXof3qvkbq3f1Kxatc9fRkSxhMh8EeeWuAUIY2rU=";
  #   };

  #   buildInputs = [ pkgs.nodejs pkgs.pnpm pkgs.typescript pkgs.pnpm.configHook ];

  #   buildPhase = ''
  #     cp -r ${src}/* ./
  #     pnpm build
  #     mkdir -p $out
  #     cp -r ./* $out/
  #   '';
  # };
  # Set NODE_PATH to point to the fetched pnpm dependencies
    #NODE_PATH = "${pnpmDeps}/node_modules";
    #export NODE_PATH="${pnpmDeps}/node_modules:$NODE_PATH"
    #mkdir -p ${TMPDIR}/cache ${TMPDIR}/data
    #installPhase
      # Link dependencies into the build environment
      # Run the build in the source directory
     # pushd ${src}
     # pnpm install  # Ensure dependencies are installed
     # pnpm build    # Run the build process

      # Copy built files and binaries to $out
    #  popd
    #  mkdir -p $out/bin
    #  cp -r ${src}/dist/* $out/  # Adjust if build output goes elsewhere
     # ln -s ./dist/pnpm-lock-to-npm-lock.js ./bin/pnpm-lock-to-npm-lock
  # Main derivation using `pnpm-lock-to-npm-lock` to convert pnpm-lock.yaml to package-lock.json
  # npmDeps = pkgs.buildNpmPackage rec {
  #   pname = "vencord-deps";
  #   version = "1.0.0";
  #   src = repo;

  #   #nativeBuildInputs = [ pkgs.nodejs pkgs.pnpm ];

  #   # Convert pnpm lockfile to npm lockfile before build
  #   postPatch = ''
  #     export RUST_BACKTRACE=1
  #     ${pnpmLockToNpmLock}/bin/pnpm-lock-to-npm-lock pnpm-lock.yaml
  #   '';
  #   buildPhase = ''
  #   '';
  # };

  # Main derivation that depends on `pnpm-lock-to-npm-loc
in
stdenv.mkDerivation {
  inherit pname version owner;

  outputs = [ "out" "api" "node_modules" ];

  src = repo;

  pnpmDeps = pnpm.fetchDeps {
    inherit pname repo;

    hash = "sha256-YBWe4MEmFu8cksOIxuTK0deO7q0QuqgOUc9WkUNBwp0=";
  };

  nativeBuildInputs = [
    git
    nodejs
    pnpm.configHook
    esbuild
  #  pnpmDeps
   # pnpmToNPM
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
    pwd=$(pwd)
    api_path=$api
    #node_module_path=node_modules

    mkdir -p "$api_path"
    mv src/api/* "$api_path/"
    rmdir src/api
    ln -sf "$api_path" src/api

    #path.resolve("'"node_modules"'", "nanoid/index.js")
    # Link the pre-fetched node_modules
    #mkdir -p node_modules
   # ln -sf "$node_module_path" node_modules

    mkdir -p lib/nanoid/dist
    cp -r node_modules/nanoid/* lib/nanoid/
    esbuild lib/nanoid/index.js --format=esm --bundle --outdir=lib/nanoid/dist/

    runHook preBuild

    substituteInPlace ./scripts/build/common.mjs \
      --replace-warn 'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*"]' \
              'external: ["~plugins", "~git-hash", "~git-remote", "/assets/*", "@api/*", "nanoid"]' \
      --replace-warn 'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin]' \
        'plugins: [fileUrlPlugin, gitHashPlugin, gitRemotePlugin, stylePlugin, { name: "api-alias-plugin", setup(build) { build.onResolve({ filter: /^@api\// }, async (args) => { const fs = await import("fs"); const path = await import("path"); let resolvedPath = args.path.replace(/^@api/, "'"$api_path"'"); const extensions = [".ts", ".tsx", ".js", ".jsx"]; for (const ext of extensions) { const testPath = path.resolve(resolvedPath + ext); if (fs.existsSync(testPath)) { return { path: testPath }; } } if (fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory()) { resolvedPath = path.join(resolvedPath, "index"); for (const ext of extensions) { const testPath = resolvedPath + ext; if (fs.existsSync(testPath)) { return { path: testPath }; } } } return { path: resolvedPath }; }); } }, { name: "nanoid-alias-plugin", setup(build) { build.onResolve({ filter: /^nanoid$/ }, async (args) => { const path = await import("path"); return { path: "$pwd/lib/nanoid/index.js" }; }); } }]'  \

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
