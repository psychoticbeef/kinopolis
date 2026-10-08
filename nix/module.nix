flake: { config, lib, pkgs, ... }:
let
  cfg = config.services.kino-watch;
in {
  options.services.kino-watch = {
    enable = lib.mkEnableOption "hourly Kinopolis OV ticket notifications via Pushover";
    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The kino-watch package.";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      default = ../watches.tsv;
      description = "Watch configuration (film ID, mode and URL).";
    };
    pushoverEnvironmentFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime secret file containing PUSHOVER_TOKEN and PUSHOVER_USER. Never use a Nix store path for secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.kino-watch = {
      description = "Check Kinopolis OV tickets and notify via Pushover";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        KINO_CONFIG = toString cfg.configFile;
        KINO_STATE_DIR = "/var/lib/kino-watch";
        KINO_NOTIFY = "${cfg.package}/lib/kino-watch/hooks/pushover.example";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/kino-watch check";
        EnvironmentFile = cfg.pushoverEnvironmentFile;
        DynamicUser = true;
        StateDirectory = "kino-watch";
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        TimeoutStartSec = "10min";
      };
    };
    systemd.timers.kino-watch = {
      description = "Hourly Kinopolis ticket check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
