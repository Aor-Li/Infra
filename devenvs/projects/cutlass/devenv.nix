# Project Dev Env：NVIDIA/cutlass（跟随 main，当前 4.8.x）。
# 构建模式（Linux + NVIDIA）：CMake + Ninja 构建 examples / 单元测试 / profiler；CuTe DSL 以 editable 方式装进 venv。
# 分析模式（macOS）：clangd 读 include/ examples/ test/ tools/，basedpyright 读 DSL 示例的 Python 层。
# 绑定：在仓库目录执行 `devenv-deploy cutlass`。
#
# 日常用法（构建目录固定为仓库里的 build/，cutlass 的 .gitignore 忽略它）：
#   devenv tasks run cutlass:configure                          # 或 CUTLASS_CMAKE_ARGS='-DCUTLASS_ENABLE_LIBRARY=OFF' ...
#   cmake --build build --target 48_hopper_warp_specialized_gemm
#   cmake --build build --target cutlass_test_unit_cute_core && ctest --test-dir build -R cute_core
#   devenv tasks run cutlass:dsl-install && python examples/python/CuTeDSL/...
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

  # CMake 的 CUTLASS_NVCC_ARCHS 写法：Hopper 必须是 90a 才能用 wgmma / TMA；Blackwell 加 100a。
  archs = [ "90a" ];
  archList = lib.concatStringsSep ";" archs;

  # 分析模式下 FetchContent 不会跑，gtest 头文件取 nixpkgs 的（版本无关紧要，只给 clangd 看）。
  gtestInclude = "${lib.getDev pkgs.gtest}/include";

  # 生成器或参数变了 compdb 就重新生成；上游增删源文件后手动 `devenv tasks run cutlass:compdb`。
  compdbStamp = builtins.hashString "sha256" "${./compdb.py} ${archList} ${gtestInclude} ${
    lib.concatStringsSep " " (cuda.clangArgs ++ cutlass.clangArgs)
  }";
  compdb = ''
    python ${./compdb.py} "$DEVENV_ROOT" "${compdbDir}"
    echo ${compdbStamp} > "${compdbDir}/stamp"
  '';

  # CMake 参数：CUTLASS_CMAKE_ARGS 非空时追加在后面（按 shell 语法解析）。
  configure = ''
    if [ -n "''${CUTLASS_CMAKE_ARGS:-}" ]; then eval "set -- $CUTLASS_CMAKE_ARGS"; else set --; fi
    cd "$DEVENV_ROOT"
    # nvcc 路径变了（cuda 模块升级 / 改 cudaHome 内容）时 CMake 只重置一部分缓存，
    # CUTLASS_NVCC_ARCHS_ENABLED 会残留成全部架构：这种情况直接清掉缓存重来。
    if [ -f build/CMakeCache.txt ] && ! grep -q "^CMAKE_CUDA_COMPILER:[A-Z]*=$CUDA_HOME/bin/nvcc$" build/CMakeCache.txt; then
      echo "cutlass: nvcc 路径变了，清掉 build/CMakeCache.txt 重新 configure" >&2
      rm -f build/CMakeCache.txt
      rm -rf build/CMakeFiles
    fi
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
      -DCMAKE_CUDA_HOST_COMPILER="$CXX" \
      -DCUDAToolkit_ROOT="$CUDA_HOME" \
      -DCUTLASS_NVCC_ARCHS="$CUTLASS_NVCC_ARCHS" \
      "$@"
  '';

  dslInstall = config.tasks."cutlass:dsl-install".exec;
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
    # 上游 CI 用 ubuntu-22.04 的 gcc 11；nixpkgs 已移除 gcc11，取 nvcc 13.0 支持范围内最接近的 13
    hostCompiler = "13";
    libraries = [
      "nvrtc" # test/unit/nvrtc
    ];
  };

  # 模块指向自己的 checkout：头文件路径与 DSL 都来自工作区
  aor.env.cutlass = {
    enable = true;
    src = config.devenv.root;
    plugins = [ "dsl" ];
  };

  aor.env.python = {
    enable = true;
    version = "3.12";
    # 锁文件跟着 Infra 走。sync 是精确的：锁变了之后 editable 安装的 DSL 会被移除，重跑 `devenv tasks run cutlass:dsl-install`。
    project = toString ./.;
    plugins = [
      "ruff"
      "basedpyright" # 分析模式验收用
      "pyright" # LazyVim 的 python extra 默认起 pyright（mason = false，要求它在 PATH 上）
    ];
  };

  env = {
    CUTLASS_NVCC_ARCHS = archList;
    CUTLASS_GTEST_INCLUDE = gtestInclude;
  };

  tasks = {
    "cutlass:compdb" = {
      description = "合成 clangd 用的 compile_commands.json";
      exec = compdb;
      after = [ "devenv:python:uv" ];
      before = [ "devenv:enterShell" ];
      status = ''test "$(cat "${compdbDir}/stamp" 2>/dev/null)" = ${compdbStamp}'';
    };

    "cutlass:configure" = {
      description = "CMake configure 到 build/（Ninja、Release、CUTLASS_NVCC_ARCHS 取环境变量）";
      exec = configure;
    };
  };

  # 唯一的测试缝：按模式验证。
  enterTest =
    if cuda.buildable then
      ''
        set -eu
        nvcc --version | grep -q "release ${cuda.version}"
        ${dslInstall}
        python -c 'import cutlass, cutlass.cute; print("CuTe DSL", cutlass.__version__)'
        ${configure}
        cmake --build build --target cutlass_test_unit_cute_core 00_basic_gemm
        ctest --test-dir build -R cute_core --output-on-failure   # 纯 host 侧
        CUDA_VISIBLE_DEVICES="''${CUDA_VISIBLE_DEVICES:-0}" ./build/examples/00_basic_gemm/00_basic_gemm
      ''
    else
      ''
        set -eu
        ${compdb}
        bash ${./check-analysis.sh} "$DEVENV_ROOT" "${compdbDir}"
      '';
}
