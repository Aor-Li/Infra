# Modular Dev Env：Python 解释器 + uv 管理的 venv。
# 关掉它你会失去：项目内锁定版本的 Python，以及按锁文件同步的 venv。
#
# 包装 devenv 内置的 languages.python：解释器来自 nixpkgs 的 python3XX，包一律由 uv
# 按 `project` 目录里的 pyproject.toml + uv.lock 同步进 $DEVENV_STATE/venv。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.aor.env.python;

  attr = "python" + lib.replaceStrings [ "." ] [ "" ] cfg.version;

  plugins = {
    ruff = pkgs.ruff;
    basedpyright = pkgs.basedpyright;
    pyright = pkgs.pyright;
  };
in
{
  options.aor.env.python = {
    enable = lib.mkEnableOption "Python 开发环境";

    version = lib.mkOption {
      type = lib.types.str;
      default = "3.12";
      description = "Python 主.次版本，映射到 nixpkgs 的 python3XX。";
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = config.devenv.root;
      defaultText = lib.literalExpression "config.devenv.root";
      description = ''
        pyproject.toml 与 uv.lock 所在目录。Project Dev Env 把它指向自己在 Infra 里的目录，
        锁文件因此跟着 Infra 提交，而不是落在上游仓库里。
      '';
    };

    syncArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--locked" ];
      description = "附加给 uv sync 的参数。默认 --locked：锁文件与 pyproject 不一致时直接报错，不静默改锁。";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames plugins));
      default = [ ];
      description = "附加的独立工具（不进 venv）。需要在 venv 里运行的工具（pytest / ipython）写进 pyproject。";
    };
  };

  config = lib.mkIf cfg.enable {
    languages.python = {
      enable = true;
      package =
        pkgs.${attr} or (throw "aor.env.python.version = \"${cfg.version}\"：当前 nixpkgs 没有 ${attr}");
      directory = cfg.project;
      venv.enable = true;
      uv = {
        enable = true;
        sync.enable = true;
        sync.arguments = cfg.syncArgs;
      };
      # PyPI 上 manylinux wheel（torch 等）需要的系统库，只给这几个。不用内置的 manylinux.enable，
      # 也不用默认的整个 profile：前者带了一份老 glibc，后者会把 nix 版 libcudart/libcublas 等排到
      # wheel 自带的 CUDA 库前面。它们都会被加到 python 包装器 LD_LIBRARY_PATH 的最前面，并传给子进程。
      libraries = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        config.stdenv.cc.cc.lib # libstdc++，与本环境的编译器同一版本
        pkgs.zlib
      ];
      # LSP 由 plugins 决定，不用内置的默认 pyright。
      lsp.enable = false;
    };

    packages = map (n: plugins.${n}) cfg.plugins;

    # 内置的 uv sync 只按 pyproject.toml 的哈希决定要不要重跑；只改了 uv.lock（如 uv lock --upgrade）时补跑一次。
    tasks."aor:python:lock-sync" = {
      description = "uv.lock 变化后重新同步 venv";
      after = [ "devenv:python:uv" ];
      before = [ "devenv:enterShell" ];
      exec = ''
        cd ${lib.escapeShellArg cfg.project}
        uv sync -p ${config.languages.python.package.interpreter} ${lib.escapeShellArgs cfg.syncArgs}
        sha256sum uv.lock > "$DEVENV_STATE/uv.lock.sha256"
      '';
      status = ''cd ${lib.escapeShellArg cfg.project} && sha256sum -c --status "$DEVENV_STATE/uv.lock.sha256" 2>/dev/null'';
    };
  };
}
