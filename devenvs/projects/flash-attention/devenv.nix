# Project Dev Env：Dao-AILab/flash-attention（跟随 main）。
# 构建模式（Linux + NVIDIA）：构建 FA2 / FA3、安装 FA4、跑测试。
# 分析模式（macOS）：clangd 读 csrc/ 与 hopper/，basedpyright 读 Python 层。
# 绑定：在仓库目录执行 `devenv-deploy flash-attention`。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cuda = config.aor.env.cuda;
  cutlass = config.aor.env.cutlass;
  state = config.devenv.state;
  compdbDir = "${state}/compdb";

  # FA2 的架构写法是 "90;100"
  faArchs = lib.concatMapStringsSep ";" (lib.replaceStrings [ "." ] [ "" ]) cuda.archs;

  # 生成器或 CUDA 参数变了 compdb 就重新生成；上游增删源文件后手动 `devenv tasks run fa:compdb`。
  compdbStamp = builtins.hashString "sha256" "${./compdb.py} ${
    lib.concatStringsSep " " (cuda.clangArgs ++ cutlass.clangArgs)
  }";
  compdb = ''
    python ${./compdb.py} "$DEVENV_ROOT" "${compdbDir}"
    echo ${compdbStamp} > "${compdbDir}/stamp"
  '';

  fa2Build = ''
    cd "$DEVENV_ROOT"
    uv pip install --no-build-isolation --no-deps -e .
  '';

  # pytest 参数：FA_TEST_ARGS 非空时整体替换默认值（按 shell 语法解析）。
  pytest = defaults: ''
    if [ -n "''${FA_TEST_ARGS:-}" ]; then eval "set -- $FA_TEST_ARGS"; else set -- ${defaults}; fi
    cd "$DEVENV_ROOT"
    CUDA_VISIBLE_DEVICES="''${CUDA_VISIBLE_DEVICES:-0}" python -m pytest -q -x "$@"
  '';

  # 默认的 FA2 测试子集：几分钟内跑完。
  fa2Test = pytest ''tests/test_flash_attn.py -k "test_flash_attn_qkvpacked and 128 and not 0.17"'';
  fa4Test = pytest "tests/cute/test_flash_attn.py";
in
{
  aor.env.cpp = {
    enable = true;
    compiler = "clang"; # 构建平台上 stdenv 由 cuda.hostCompiler 接管
    compileCommandsDir = compdbDir;
    clangdSystemHeaders = false; # compdb 用 cuda.clangArgs，自带完整头文件路径
  };

  aor.env.cuda = {
    enable = true;
    version = "13.0";
    archs = [
      "9.0" # H100
      "10.0" # B200
    ];
    # 上游 CI 用 ubuntu-22.04 自带的 gcc 11；nixpkgs 已移除 gcc11，取 nvcc 13.0 支持范围内最接近的 13
    hostCompiler = "13";
    # torch 的 ATen/cuda 头文件会连带引用这些库的头文件
    libraries = [
      "cublas"
      "cusparse"
      "cusolver"
      "curand"
      "nvml"
    ];
  };

  # 上游 vendor 了 cutlass 子模块，版本跟上游走；DSL 直接用 wheel（pyproject 里的 nvidia-cutlass-dsl），不 editable
  aor.env.cutlass = {
    enable = true;
    src = "${config.devenv.root}/csrc/cutlass";
  };

  aor.env.python = {
    enable = true;
    version = "3.12";
    # 锁文件跟着 Infra 走。sync 是精确的：锁变了之后 editable 安装的 flash-attn 会被移除，
    # 重跑 `devenv tasks run fa2:build`（build/ 里有增量产物，很快）。
    project = toString ./.;
    plugins = [
      "ruff"
      "basedpyright" # 分析模式验收用
      "pyright" # LazyVim 的 python extra 默认起 pyright（mason = false，要求它在 PATH 上）
    ];
  };

  env = {
    FLASH_ATTENTION_FORCE_BUILD = "TRUE"; # 不去 GitHub 下载预编译 wheel
    FLASH_ATTN_CUDA_ARCHS = faArchs;
    # MAX_JOBS 不设：setup.py 按核数与空闲内存自己算
  };

  tasks = {
    "fa:compdb" = {
      description = "合成 clangd 用的 compile_commands.json";
      exec = compdb;
      after = [ "devenv:python:uv" ];
      before = [ "devenv:enterShell" ];
      status = ''test "$(cat "${compdbDir}/stamp" 2>/dev/null)" = ${compdbStamp}'';
    };

    "fa2:build" = {
      description = "以 editable 方式构建 FA2（flash_attn_2_cuda）";
      exec = fa2Build;
    };

    "fa3:build" = {
      description = "以 editable 方式构建 FA3（hopper/，只编 sm90，很慢）";
      exec = ''
        cd "$DEVENV_ROOT/hopper"
        uv pip install --no-build-isolation --no-deps -e .
      '';
    };

    "fa4:install" = {
      description = "以 editable 方式安装 FA4（flash_attn/cute，JIT，无需构建）";
      exec = ''uv pip install --no-deps -e "$DEVENV_ROOT/flash_attn/cute"'';
    };

    "fa4:test" = {
      description = "跑 FA4 测试（单卡）";
      after = [ "fa4:install" ];
      exec = fa4Test;
    };
  };

  enterShell = ''
    git -C "$DEVENV_ROOT" submodule status csrc/cutlass 2>/dev/null | grep -q '^-' \
      && echo "flash-attention: csrc/cutlass 子模块未初始化：git submodule update --init csrc/cutlass" >&2
    true
  '';

  # 唯一的测试缝：按模式验证。
  enterTest =
    if cuda.buildable then
      ''
        set -eu
        nvcc --version | grep -q "release ${cuda.version}"
        python -c 'import sys, torch; v = torch.version.cuda or ""; sys.exit(0 if v.startswith("${cuda.version}") else "torch CUDA: " + v)'
        ${fa2Build}
        ${fa2Test}
      ''
    else
      ''
        set -eu
        ${compdb}
        bash ${./check-analysis.sh} "$DEVENV_ROOT" "${compdbDir}"
      '';
}
