{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixcord;

  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    attrsets
    lists
    ;
    
  vencordPkgs = pkgs.callPackage ./vencord.nix {
    inherit (pkgs)
      curl
      esbuild
      fetchFromGitHub
      git
      jq
      lib
      nix-update
      nodejs
      pnpm
      stdenv
      writeShellScript
      ;
    buildWebExtension = false;
  };
    
  applyPostPatch = pkg: 
    pkg.overrideAttrs (oldAttrs: {
      passthru = {
        userPlugins = userPluginsDirectory;
      };

      postPatch = '' 
        ln -s ${userPluginsDirectory} src/userplugins
      '';
    });
  patchedVencord = applyPostPatch vencordPkgs;

  dop = with types; coercedTo package (a: a.outPath) pathInStore;

  # Define regular expressions for GitHub and Git URLs
  regexGithub = "github:([[:alnum:].-]+)/([[:alnum:]/-]+)/([0-9a-f]{40})";
  regexGit = "git[+]file:///([^/]+/)*([^/?]+)(\\?ref=[a-f0-9]{40})?$";

  # Define coercion functions for GitHub and Git
  coerceGithub = value: let
    matches = builtins.match regexGithub value;
    owner = builtins.elemAt matches 0;
    repo = builtins.elemAt matches 1;
    rev = builtins.elemAt matches 2;
  in builtins.fetchGit {
    url = "https://github.com/${owner}/${repo}";
    inherit rev;
  };

  coerceGit = value: let
    # Match using regex, assuming regexGit is defined and captures groups correctly
    matches = builtins.match regexGit value;

    # Set rev only if matches are found
    rev = if matches != null then
      let
        rawRev = builtins.elemAt matches 2;
      in
        if rawRev != null && builtins.substring 0 5 rawRev == "?ref="
        then builtins.substring 5 (builtins.stringLength rawRev) rawRev
        else null
    else null;

    # Set filepath only if matches are found
    filepath = if matches != null then
      let
        startOffset = 4;  # Remove 4 characters from the beginning
        endOffset = 45;   # Remove 45 characters from the end
        fullLength = builtins.stringLength value;
        adjustedPathLength = fullLength - startOffset - endOffset;
      in
        builtins.substring startOffset adjustedPathLength value
    else null;

  in if filepath != null then
    # Call fetchGit only if filepath is valid
    builtins.fetchGit (
      let
        # Only include rev if it's non-null and non-empty
        revCondition = if rev != null && rev != "" then { rev = rev; } else {};
      in {
        url = filepath;
        ref = "main";
      } // revCondition  
    )
  else
    throw "Failed to extract a valid filepath from the given value";
#in coerceGit


  # Mapper function that applies coercion based on the regex match
  pluginMapper = plugin: 
    if builtins.match regexGithub plugin != null then
      coerceGithub plugin
    else if builtins.match regexGit plugin != null then
      coerceGit plugin
    else if lib.attrsets.isDerivation plugin then
      plugin
    else
      builtins.toPath plugin;
      # Wrap `plugin` in a basic derivation if it's not already a derivation
      # lib.traceValFn (d: d.outPath) (pkgs.runCommand "plugin-${builtins.hashString "sha256" (toString plugin)}" {
      #   buildInputs = []; # Add any dependencies here if needed
      # } ''
      #   mkdir -p $out
        
      #   # Check if the plugin directory exists and copy contents directly to $out
      #   if [ -d "${builtins.toPath plugin}" ]; then
      #     cp -rT ${builtins.toPath plugin} $out
      #   else
      #     echo "Warning: ${builtins.toPath plugin} does not exist or is empty."
      #   fi
      # '');





  recursiveUpdateAttrsList = list:
    if (builtins.length list <= 1) then (builtins.elemAt list 0) else
      recursiveUpdateAttrsList ([
        (attrsets.recursiveUpdate (builtins.elemAt list 0) (builtins.elemAt list 1))
      ] ++ (lists.drop 2 list));

  pluginDerivations = lib.mapAttrs (_: plugin: pluginMapper plugin) cfg.userPlugins;

  buildDirs = pluginDerivations: lib.mapAttrsToList (name: pluginDir:
    let
      fullPath = "${pluginDir}";

      # Check for a Nix expression and build if present
      buildIfExists = if builtins.pathExists "${fullPath}/default.nix" || builtins.pathExists "${fullPath}/shell.nix" then
        import fullPath { inherit pkgs vencordPkgs patchedVencord; }

      else
        pluginDir;
    in
      # Return an attribute set with a `name` and `path` for linkFarm
      { name = name; path = buildIfExists; }
  ) pluginDerivations;
  # Build the user plugins directory with linkFarm
  userPluginsDirectory = pkgs.linkFarm "userPlugins" (buildDirs pluginDerivations);

in   
{
  #inherit patchedVencord;
  options.programs.nixcord = {
    enable = mkEnableOption "Enables Discord with Vencord";
    discord = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable discord
          Disable to only install Vesktop
        '';
      };
      package = mkOption {
        type = types.package;
        default = pkgs.discord;
        description = ''
          The Discord package to use
        '';
      };
      configDir = mkOption {
        type = types.path;
        default = "${if pkgs.stdenvNoCC.isLinux then config.xdg.configHome else "${config.home.homeDirectory}/Library/Application Support"}/discord";
        description = "Config path for Discord";
      };
      vencord.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Vencord (for non-vesktop)";
      };
      openASAR.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable OpenASAR (for non-vesktop)";
      };
      settings = mkOption {
        type = types.attrs;
        default = {};
        description =  ''
          Settings to be placed in discordConfigDir/settings.json
        '';
      };
    };
    vesktop = {
      enable = mkEnableOption ''
        Whether to enable Vesktop
      '';
      package = mkOption {
        type = types.package;
        default = pkgs.vesktop;
        description = ''
          The Vesktop package to use
        '';
      };
      configDir = mkOption {
        type = types.path;
        default = "${if pkgs.stdenvNoCC.isLinux then config.xdg.configHome else "${config.home.homeDirectory}/Library/Application Support"}/vesktop";
        description = "Config path for Vesktop";
      };
      settings = mkOption {
        type = types.attrs;
        default = {};
        description =  ''
          Settings to be placed in vesktop.configDir/settings.json
        '';
      };
      state = mkOption {
        type = types.attrs;
        default = {};
        description =  ''
          Settings to be placed in vesktop.configDir/state.json
        '';
      };
    };
    package = mkOption {
      type = with types; nullOr package;
      default = null;
      description = ''
        Deprecated
        The Discord package to use
      '';
    };
    vesktopPackage = mkOption {
      type = with types; nullOr package;
      default = null;
      description = ''
        The Vesktop package to use
      '';
    };
    configDir = mkOption {
      type = types.path;
      default = "${if pkgs.stdenvNoCC.isLinux then config.xdg.configHome else "${config.home.homeDirectory}/Library/Application Support"}/Vencord";
      description = "Vencord config directory";
    };
    vesktopConfigDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Config path for Vesktop";
    };
    vencord.enable = mkOption {
      type = with types; nullOr bool;
      default = null;
      description = "Enable Vencord (for non-vesktop)";
    };
    openASAR.enable = mkOption {
      type = with types; nullOr bool;
      default = null;
      description = "Enable OpenASAR (for non-vesktop)";
    };
    quickCss = mkOption {
      type = types.str;
      default = "";
      description = "Vencord quick CSS";
    };
    config = {
      notifyAboutUpdates = mkEnableOption "Notify when updates are available";
      autoUpdate = mkEnableOption "Automaticall update Vencord";
      autoUpdateNotification = mkEnableOption "Notify user about auto updates";
      useQuickCss = mkEnableOption "Enable quick CSS file";
      themeLinks = mkOption {
        type = with types; listOf str;
        default = [ ];
        description = "A list of links to online vencord themes";
        example = [ "https://raw.githubusercontent.com/rose-pine/discord/main/rose-pine.theme.css" ];
      };
      enabledThemes = mkOption {
        type = with types; listOf str;
        default = [ ];
        description = "A list of themes to enable from themes directory";
      };
      enableReactDevtools = mkEnableOption "Enable React developer tools";
      frameless = mkEnableOption "Make client frameless";
      transparent = mkEnableOption "Enable client transparency";
      disableMinSize = mkEnableOption "Disable minimum window size for client";
      plugins = import ./plugins.nix { inherit lib; };
    };
    vesktopConfig = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        additional config to be added to programs.nixcord.config
        for vesktop only
      '';
    };
    vencordConfig = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        additional config to be added to programs.nixcord.config
        for vencord only
      '';
    };
    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        additional config to be added to programs.nixcord.config
        for both vencord and vesktop
      '';
    };
    userPlugins = lib.mkOption {
      description = "User plugin to fetch and install. Note that any JSON required must be enabled in extraConfig.";
      
      # Define the type of userPlugins with validation
      type = types.attrsOf (types.oneOf [
        (types.strMatching regexGithub)   # GitHub URL pattern
        (types.strMatching regexGit)      # Git URL pattern
        types.package                      # Nix packages
        types.path                         # Nix paths
      ]);

      # Set default values by mapping the userPlugins with the pluginMapper
      #default = lib.mapAttrs (_: plugin: pluginMapper plugin) cfg.userPlugins;

      # Example usage of the userPlugins option
      example = {
        someCoolPlugin = "github:someUser/someCoolPlugin/someHashHere";  # GitHub example
        anotherCoolPlugin = "git+file:///path/to/repo?rev=abcdef1234567890abcdef1234567890abcdef12";  # File path example
      };
    };

    parseRules = {
      upperNames = mkOption {
        type = with types; listOf str;
        description = "option names to become UPPER_SNAKE_CASE";
        default = [];
      };
      lowerPluginTitles = mkOption {
        type = with types; listOf str;
        description = "plugins with lowercase names in json";
        default = [];
        example = [ "petpet" ];
      };
      fakeEnums = {
        zero = mkOption {
          type = with types; listOf str;
          description = "strings to evaluate to 0 in JSON";
          default = [];
        };
        one = mkOption {
          type = with types; listOf str;
          description = "strings to evaluate to 1 in JSON";
          default = [];
        };
        two = mkOption {
          type = with types; listOf str;
          description = "strings to evaluate to 2 in JSON";
          default = [];
        };
        three = mkOption {
          type = with types; listOf str;
          description = "strings to evaluate to 3 in JSON";
          default = [];
        };
        four = mkOption {
          type = with types; listOf str;
          description = "string to evalueate to 4 in JSON";
          default = [];
        };
        # I've never seen a plugin with more than 5 options for 1 setting
      };
    };
  };

  config = let
    parseRules = cfg.parseRules;
    inherit (pkgs.callPackage ./lib.nix { inherit lib parseRules; })
      mkVencordCfg;
    vencord = patchedVencord;
    isQuickCssUsed = appConfig: (cfg.config.useQuickCss || appConfig ? "useQuickCss" && appConfig.useQuickCss) && cfg.quickCss != "";
  in mkIf cfg.enable (mkMerge [
    {
      home.packages = [
        (mkIf cfg.discord.enable (cfg.discord.package.override {
          withVencord = cfg.discord.vencord.enable;
          withOpenASAR = cfg.discord.openASAR.enable;
          inherit vencord;
        }))
        (mkIf cfg.vesktop.enable (cfg.vesktop.package.override {
          withSystemVencord = true;
          inherit vencord;
        }))
      ];
    }
    (mkIf cfg.discord.enable (mkMerge [
      # QuickCSS
      (mkIf (isQuickCssUsed cfg.vencordConfig) {
        home.file."${cfg.configDir}/settings/quickCss.css".text = cfg.quickCss;
      })
      # Vencord Settings
      {
        home.file."${cfg.configDir}/settings/settings.json".text =
          builtins.toJSON (mkVencordCfg (
            recursiveUpdateAttrsList [ cfg.config cfg.extraConfig cfg.vencordConfig ]
          ));
      }
      # Client Settings
      (mkIf (cfg.discord.settings != {}) {
        home.file."${cfg.discord.configDir}/settings.json".text =
            builtins.toJSON mkVencordCfg cfg.discord.settings;
      })
    ]))
    (mkIf cfg.vesktop.enable (mkMerge [
      # QuickCSS
      (mkIf (isQuickCssUsed cfg.vesktopConfig) {
        home.file."${cfg.vesktop.configDir}/settings/quickCss.css".text = cfg.quickCss;
      })
      # Vencord Settings
      {
        home.file."${cfg.vesktop.configDir}/settings/settings.json".text =
          builtins.toJSON (mkVencordCfg (
            recursiveUpdateAttrsList [ cfg.config cfg.extraConfig cfg.vesktopConfig ]
          ));
      }
      # Vesktop Client Settings
      (mkIf (cfg.vesktop.settings != {}) {
        home.file."${cfg.vesktop.configDir}/settings.json".text =
            builtins.toJSON mkVencordCfg cfg.vesktopSettings;
      })
      # Vesktop Client State
      (mkIf (cfg.vesktop.state != {}) {
        home.file."${cfg.vesktop.configDir}/state.json".text =
            builtins.toJSON mkVencordCfg cfg.vesktopState;
      })
    ]))
    # Warnings
    {
      warnings = import ./warnings.nix { inherit cfg mkIf; };
    }
  ]);
}
