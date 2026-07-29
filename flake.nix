{
  description = "A fork of the multi-platform proxy client FlClash, based on original Mihomo Core, simple and easy to use, open source and ad-free.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        version = self.shortRev or self.dirtyShortRev or "unknown";

        # HASHES
        # ==========================================================

        vendorHash = "sha256-BsFT/KrD8SX3edFtipK/eaJvVopvOCmTiw+Ydh+oa0s=";
        gitHashes = {
          flutter_js = "sha256-4PgiUL7aBnWVOmz2bcSxKt81BRVMnopabj5LDbtPYk4=";
        };

        # ==========================================================

        src = pkgs.lib.cleanSource ./.;

        flclashCore = pkgs.buildGoModule {
          pname = "flclashx-core";
          inherit version src vendorHash;
          modRoot = "core";
          env = {
            CGO_ENABLED = "0";
          };
          buildPhase = ''
            runHook preBuild
            go build \
              -tags=with_gvisor \
              -trimpath \
              -ldflags="-w -s -X github.com/metacubex/mihomo/constant.Version=${version}" \
              -o FlClashCore .
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 FlClashCore $out/bin/FlClashCore
            runHook postInstall
          '';
          doCheck = false;
        };

        flclashx = pkgs.flutter.buildFlutterApplication {
          pname = "flclashx";
          inherit version src gitHashes;
          pubspecLock = builtins.fromJSON (
            builtins.readFile (
              pkgs.runCommand "pubspec.lock.json" { } ''
                ${pkgs.yq-go}/bin/yq -o=json ${./pubspec.lock} > $out
              ''
            )
          );
          preBuild = ''
            mkdir -p libclash/linux
            cp ${flclashCore}/bin/FlClashCore libclash/linux/FlClashCore
          '';
          nativeBuildInputs = with pkgs; [
            pkg-config
            wrapGAppsHook3
          ];
          buildInputs = with pkgs; [
            gtk3
            glib
            gdk-pixbuf
            cairo
            pango
            atk
            harfbuzz
            libepoxy
            libayatana-appindicator
            keybinder3
            libX11
            libXcursor
            libXrandr
            libXinerama
            libXi
          ];
          meta = with pkgs.lib; {
            homepage = "https://github.com/pluralplay/FlClashX";
            license = licenses.gpl3Only;
            mainProgram = "FlClashX";
            platforms = platforms.linux;
          };
        };
      in
      {
        packages = rec {
          default = flclashx;
          inherit flclashx;
          flclashx-core = flclashCore;
        };
        devShells.default = pkgs.mkShell {
          inputsFrom = [ flclashx ];
          nativeBuildInputs = with pkgs; [
            flutter
            go
            yq-go
          ];
        };
      }
    )
    // {
      overlays.default = final: prev: {
        flclashx = self.packages.${final.system}.flclashx;
      };
    };
}
