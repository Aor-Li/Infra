# 关掉它你会失去：devenv 本体、进入已绑定目录时自动激活 Project Dev Env 的 shell hook，
# 以及把上游仓库绑定到 `<repo>/devenvs/projects/<name>` 的 devenv-deploy。
{
  den.aspects.dev.env.devenv.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      root = config.lib.repo.root;

      # 在当前目录绑定 `<root>/devenvs/projects/<project>/`（devenv --from ... allow），并把
      # devenv 生成在项目里的状态与缓存写进 .git/info/exclude。上游仓库里不放任何配置文件。
      # 用法与新建 Project Dev Env 的步骤见仓库根的 devenvs/README.md。
      devenv-deploy = pkgs.writeShellApplication {
        name = "devenv-deploy";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gnugrep
          pkgs.devenv
        ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "Usage: devenv-deploy <project-name>" >&2
            echo "可用的 Project Dev Env：" >&2
            ls "${root}/devenvs/projects" >&2
            exit 1
          fi

          project="$1"
          src="${root}/devenvs/projects/$project"

          if [ ! -f "$src/devenv.nix" ]; then
            echo "error: Project Dev Env 不存在：$src" >&2
            exit 1
          fi

          for f in devenv.nix devenv.yaml .envrc; do
            if [ -e "$f" ] || [ -L "$f" ]; then
              echo "error: 当前目录已有 $f；绑定方式下项目里不应有 devenv 配置，先移走它" >&2
              exit 1
            fi
          done

          devenv --from "path:$src" allow

          if git rev-parse --git-dir >/dev/null 2>&1; then
            exclude="$(git rev-parse --git-path info/exclude)"
            mkdir -p "$(dirname "$exclude")"
            touch "$exclude"
            for pattern in /.devenv/ /devenv.lock; do
              grep -qxF "$pattern" "$exclude" || echo "$pattern" >>"$exclude"
            done
            echo "excluded: /.devenv/ /devenv.lock → $exclude"
          fi

          echo "bound: $PWD → $src（新开一个提示符或 cd 进来即激活）"
        '';
      };
    in
    {
      home.packages = [
        pkgs.devenv
        devenv-deploy
      ];

      # devenv 自带的目录 hook：进入已 allow 的目录时激活环境。fish 的包里没有 vendor_conf.d，三种 shell 都显式挂上。
      programs.bash.initExtra = ''eval "$(${lib.getExe pkgs.devenv} hook bash)"'';
      programs.zsh.initContent = ''eval "$(${lib.getExe pkgs.devenv} hook zsh)"'';
      programs.fish.interactiveShellInit = "${lib.getExe pkgs.devenv} hook fish | source";
    };
}
