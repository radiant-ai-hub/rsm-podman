{
  description = "Nix runtime profile for the RSM Podman Nix image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          }));
    in
    {
      packages = forAllSystems (pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          quartoVersion = "1.9.13";
          quartoSources = {
            aarch64-linux = {
              arch = "arm64";
              hash = "sha256-cLZN/KWynNPy94ujLRSnmfox2Yey1WTvO69+dTywn/U=";
            };
            x86_64-linux = {
              arch = "amd64";
              hash = "sha256-NsKQGDqnDP0IaBrLh4cXKU6gPg67Skk/LsPLQoSxa88=";
            };
          };
          quartoSource = quartoSources.${system};
          quartoBin = pkgs.stdenvNoCC.mkDerivation {
            pname = "quarto-bin";
            version = quartoVersion;

            src = pkgs.fetchurl {
              url = "https://github.com/quarto-dev/quarto-cli/releases/download/v${quartoVersion}/quarto-${quartoVersion}-linux-${quartoSource.arch}.deb";
              hash = quartoSource.hash;
            };

            nativeBuildInputs = with pkgs; [
              autoPatchelfHook
              dpkg
            ];

            buildInputs = with pkgs; [
              curl
              openssl
              stdenv.cc.cc.lib
              zlib
            ];

            unpackPhase = ''
              dpkg-deb -x "$src" .
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out/opt" "$out/bin"
              cp -a opt/quarto "$out/opt/quarto"
              ln -s "$out/opt/quarto/bin/quarto" "$out/bin/quarto"

              runHook postInstall
            '';
          };
          glibcCompat = pkgs.runCommand "glibc-compat" { } ''
            mkdir -p "$out/lib"
            for name in libc.so libc.so.6; do
              if [ -e "${pkgs.glibc}/lib/$name" ]; then
                ln -s "${pkgs.glibc}/lib/$name" "$out/lib/$name"
              fi
            done
            for loader in ${pkgs.glibc}/lib/ld-linux*.so*; do
              [ -e "$loader" ] || continue
              ln -s "$loader" "$out/lib/$(basename "$loader")"
            done
          '';
        in
        {
          quarto-bin = quartoBin;
          glibc-compat = glibcCompat;

          runtimeEnv = pkgs.buildEnv {
            name = "rsm-podman-nix-runtime";
            paths = with pkgs; [
              bashInteractive
              binutils
              cacert
              coreutils
              curl
              diffutils
              findutils
              gawk
              gh
              git
              git-lfs
              glibc.bin
              glibcLocales
              gnugrep
              gnused
              gnutar
              gosu
              gzip
              htop
              less
              lsof
              nix
              oh-my-zsh
              openssh
              openssl
              pgweb
              postgresql_16
              procps
              python313
              quartoBin
              rsync
              shadow
              stdenv.cc.cc.lib
              sudo
              unzip
              uv
              vim
              vifm
              wget
              which
              xz
              zip
              autojump
              zsh
              zsh-autosuggestions
              zsh-completions
              zsh-history-substring-search
              zsh-powerlevel10k
              zsh-syntax-highlighting
            ];
            pathsToLink = [ "/bin" "/etc" "/lib" "/share" ];
          };

        default = pkgs.buildEnv {
          name = "rsm-podman-nix-default";
          paths = [ self.packages.${system}.runtimeEnv ];
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            docker
            git
            nix
            uv
          ];
        };
      });
    };
}
