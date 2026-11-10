# 关掉它你会失去：devenv 本体、进入已绑定目录时自动激活 Project Dev Env 的 shell hook，
# 以及把上游仓库绑定到 `<repo>/devenvs/projects/<name>` 的 devenv-deploy（顺带给 VSCode 写好 clangd 配置）。
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
          pkgs.jq
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

          excludes=(/.devenv/ /devenv.lock)

          # VSCode（尤其 Remote-SSH）的扩展进程不经过 shell hook，拿不到 CLANGD_FLAGS。
          # 把 clangd 的路径与参数写进 .vscode/settings.json；clangd.path 指向 .devenv/profile 软链，
          # 环境重建后自动跟上。参数取自 Project Dev Env 求值出的 CLANGD_FLAGS（cpp 模块是唯一来源）。
          settings=.vscode/settings.json
          echo "evaluating Project Dev Env（首次可能要几分钟）…"
          flags="$(devenv --from "path:$src" print-dev-env --json | jq -r '.variables.CLANGD_FLAGS.value // empty')"
          if [ -z "$flags" ]; then
            echo "skip $settings：该环境没有 CLANGD_FLAGS（未启用 cpp 模块）"
          elif git ls-files --error-unmatch "$settings" >/dev/null 2>&1; then
            echo "warning: $settings 由上游仓库跟踪，不改它；clangd 参数需手动配置：$flags" >&2
          else
            patch="$(jq -n --arg path "$PWD/.devenv/profile/bin/clangd" --arg flags "$flags" \
              '{"clangd.path": $path, "clangd.arguments": ($flags | split(" ") | map(select(. != "")))}')"
            mkdir -p .vscode
            if [ ! -s "$settings" ]; then
              echo "$patch" >"$settings"
            elif merged="$(jq --argjson p "$patch" '. + $p' "$settings" 2>/dev/null)"; then
              echo "$merged" >"$settings"
            else
              echo "warning: $settings 不是纯 JSON（含注释？），没有合并；请手动加入：" >&2
              echo "$patch" >&2
            fi
            echo "clangd → $settings"
            excludes+=("/$settings")
          fi

          if git rev-parse --git-dir >/dev/null 2>&1; then
            exclude="$(git rev-parse --git-path info/exclude)"
            mkdir -p "$(dirname "$exclude")"
            touch "$exclude"
            for pattern in "''${excludes[@]}"; do
              grep -qxF "$pattern" "$exclude" || echo "$pattern" >>"$exclude"
            done
            echo "excluded: ''${excludes[*]} → $exclude"
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
