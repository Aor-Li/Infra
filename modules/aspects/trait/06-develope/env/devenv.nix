{ ... }:
{
  den.aspects.dev.env.devenv.homeManager =
    { config, pkgs, ... }:
    let
      # 仓库根路径。源仓库把它写死为 /home/aor/infra（并留有兼容 TODO），
      # 这里改为从 home 目录推导，与 feature/nix/nh.nix 的约定一致。
      root = "${config.home.homeDirectory}/Den-Infra";

      # TODO: 该脚本依赖 `<root>/devenvs/<project>` 目录，但该目录目前并不存在
      # （源仓库亦然），直接运行会报 "project devenv directory not found"。
      # 需要时再补建 devenvs/ 或重写此脚本。
      devenv-deploy = pkgs.writeShellApplication {
        name = "devenv-deploy";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          set -eu

          ROOT="${root}"

          usage() {
            echo "Usage: devenv-deploy <project-name>" >&2
            exit 1
          }

          if [ "$#" -ne 1 ]; then
            usage
          fi

          project="$1"
          src_dir="$ROOT/devenvs/$project"

          if [ ! -d "$src_dir" ]; then
            echo "error: project devenv directory not found: $src_dir" >&2
            exit 1
          fi

          check_source() {
            name="$1"
            src="$src_dir/$name"

            if [ ! -e "$src" ]; then
              echo "error: required file missing: $src" >&2
              exit 1
            fi
          }

          deploy_one() {
            name="$1"
            src="$src_dir/$name"
            dst="./$name"

            if [ -L "$dst" ]; then
              current="$(readlink "$dst" || true)"
              if [ "$current" = "$src" ]; then
                echo "ok: $dst already points to $src"
                return 0
              fi
            fi

            if [ -e "$dst" ] && [ ! -L "$dst" ]; then
              echo "error: destination exists and is not a symlink: $dst" >&2
              exit 1
            fi

            ln -sfn "$src" "$dst"
            echo "linked: $dst -> $src"
          }

          check_source "devenv.nix"
          check_source "devenv.yaml"
          check_source ".envrc"

          deploy_one "devenv.nix"
          deploy_one "devenv.yaml"
          deploy_one ".envrc"

          echo "devenv deployment complete for project: $project"
        '';
      };
    in
    {
      home.packages = [
        pkgs.devenv
        devenv-deploy
      ];
    };
}
