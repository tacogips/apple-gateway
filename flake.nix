{
  description = "apple-gateway Swift development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      git-hooks,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        runtimePackages =
          with pkgs;
          [
            gh
            git
            go-task
            swiftlint
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [
            swift
          ];

        devOnlyPackages = with pkgs; [
          gitleaks
        ];

        preCommitCheck = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            gitleaks = {
              enable = true;
              name = "gitleaks";
              entry = "${pkgs.lib.getExe pkgs.gitleaks} git --pre-commit --redact --staged --verbose";
              language = "system";
              pass_filenames = false;
            };
          };
        };

        devPackages = runtimePackages ++ devOnlyPackages ++ preCommitCheck.enabledPackages;

        installVirtualAudioDriver = pkgs.writeShellApplication {
          name = "apple-gateway-install-virtual-audio-driver";
          text =
            if pkgs.stdenv.isDarwin then
              ''
                driver="''${1:-blackhole-2ch}"

                if [ "$#" -gt 1 ]; then
                  echo "Usage: nix run .#install-virtual-audio-driver -- [blackhole-2ch|blackhole-16ch|blackhole-64ch|vb-cable|loopback]" >&2
                  exit 2
                fi

                case "$driver" in
                  blackhole-2ch|blackhole-16ch|blackhole-64ch|vb-cable|loopback)
                    ;;
                  *)
                    echo "Unsupported virtual audio driver: $driver" >&2
                    echo "Supported casks: blackhole-2ch, blackhole-16ch, blackhole-64ch, vb-cable, loopback" >&2
                    exit 2
                    ;;
                esac

                if command -v brew >/dev/null 2>&1; then
                  brew_executable="$(command -v brew)"
                elif [ -x /opt/homebrew/bin/brew ]; then
                  brew_executable="/opt/homebrew/bin/brew"
                elif [ -x /usr/local/bin/brew ]; then
                  brew_executable="/usr/local/bin/brew"
                else
                  echo "Homebrew is required to install $driver." >&2
                  echo "Install Homebrew first, then run: nix run .#install-virtual-audio-driver -- $driver" >&2
                  exit 1
                fi

                if "$brew_executable" list --cask "$driver" >/dev/null 2>&1; then
                  echo "$driver is already installed."
                  exit 0
                fi

                echo "Installing the Homebrew cask $driver..."
                "$brew_executable" install --cask "$driver"
              ''
            else
              ''
                echo "Virtual audio driver installation is supported only on macOS." >&2
                exit 1
              '';
        };
      in
      {
        apps.install-virtual-audio-driver = {
          type = "app";
          program = lib.getExe installVirtualAudioDriver;
          meta.description = "Install a supported virtual audio driver through Homebrew on macOS";
        };

        apps.install-blackhole = {
          type = "app";
          program = lib.getExe installVirtualAudioDriver;
          meta.description = "Install the BlackHole 2ch virtual audio driver through Homebrew on macOS";
        };

        packages.dev-tools = pkgs.buildEnv {
          name = "apple-gateway-dev-tools";
          paths = devPackages;
          pathsToLink = [ "/bin" ];
        };
        packages.install-virtual-audio-driver = installVirtualAudioDriver;
        packages.install-blackhole = installVirtualAudioDriver;

        checks.pre-commit-check = preCommitCheck;

        devShells.default = pkgs.mkShell {
          packages = devPackages;

          shellHook = ''
            ${preCommitCheck.shellHook}

            echo "apple-gateway Swift development environment ready"
            echo "Swift version: $(swift --version 2>/dev/null | head -n 1 || echo 'not available')"
            echo "Task version: $(task --version 2>/dev/null || echo 'not available')"
            echo "SwiftLint version: $(swiftlint version 2>/dev/null || echo 'not available')"
            echo "Gitleaks version: $(gitleaks version 2>/dev/null || echo 'not available')"

            if [ "$(uname -s)" = "Darwin" ]; then
              if system_profiler SPAudioDataType 2>/dev/null | grep -E -q "BlackHole|Loopback|VB-CABLE|VB-Cable"; then
                echo "Compatible virtual audio driver: available"
              else
                echo "Compatible virtual audio driver: not found"
                echo "Install one explicitly with: nix run .#install-virtual-audio-driver -- blackhole-2ch"
              fi
            fi
          '';
        };
      }
    );
}
