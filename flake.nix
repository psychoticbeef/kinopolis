{
  description = "Kinopolis OV ticket watcher";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      runtimeFor = pkgs: [ pkgs.bash pkgs.curl pkgs.gawk pkgs.coreutils pkgs.gnused ]
        ++ [ (if pkgs.stdenv.hostPlatform.isLinux then pkgs.util-linux else pkgs.flock) ];
    in {
      nixosModules.default = import ./nix/module.nix self;

      packages = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "kino-watch";
            version = "1.0.0";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib/kino-watch/hooks" "$out/bin"
              cp kino-watch parse-kinopolis.awk watches.tsv "$out/lib/kino-watch/"
              cp hooks/stdout hooks/pushover.example "$out/lib/kino-watch/hooks/"
              patchShebangs "$out/lib/kino-watch"
              makeWrapper "$out/lib/kino-watch/kino-watch" "$out/bin/kino-watch" \
                --prefix PATH : ${pkgs.lib.makeBinPath (runtimeFor pkgs)} \
                --run 'export KINO_STATE_DIR="''${KINO_STATE_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/kino-watch}"'
              runHook postInstall
            '';
            meta.mainProgram = "kino-watch";
          };
        });

      devShells = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            packages = runtimeFor pkgs ++ [ pkgs.git ];
          };
        });

      checks = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          tests = pkgs.runCommand "kino-watch-tests" {
            nativeBuildInputs = runtimeFor pkgs ++ [ pkgs.diffutils ];
          } ''
            cp -R ${self} source
            chmod -R u+w source
            cd source
            patchShebangs .
            bash tests/run
            package=${self.packages.${system}.default}/bin/kino-watch
            KINO_STATE_DIR="$TMPDIR/explicit-state" "$package" status
            test -f "$TMPDIR/explicit-state/.lock"
            env -u KINO_STATE_DIR XDG_STATE_HOME="$TMPDIR/xdg-state" "$package" status
            test -f "$TMPDIR/xdg-state/kino-watch/.lock"
            env -u KINO_STATE_DIR -u XDG_STATE_HOME HOME="$TMPDIR/home" "$package" status
            test -f "$TMPDIR/home/.local/state/kino-watch/.lock"
            touch "$out"
          '';
        });
    };
}
