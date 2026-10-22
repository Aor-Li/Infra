# Modular Dev Env：CUDA 工具链。
# 关掉它你会失去：锁定版本的 nvcc / CUDA 头文件，以及 nix 环境里对宿主机 GPU 驱动的访问。
#
# 按平台降级（Project Dev Env 不做平台判断）：
#   - Linux（构建模式）：nvcc + 头文件 + 库来自 nixpkgs cudaPackages；宿主机驱动库
#     （libcuda 等）通过一个只含驱动库软链的目录加进 LD_LIBRARY_PATH。
#   - darwin（分析模式）：cudaPackages 只支持 Linux，于是从 x86_64-linux 的包集合里取
#     同一批包（纯文件，经 cache.nixos-cuda.org 替换下载，不在本机构建），拼成只给
#     clangd 用的 CUDA_HOME；不放进 PATH，也不接驱动。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.aor.env.cuda;
  inherit (pkgs.stdenv) hostPlatform;

  buildable = hostPlatform.isLinux;

  # CUDA 包的来源：Linux 用本机包集合；darwin 借 x86_64-linux 的（头文件与平台无关）。
  cudaSource =
    if buildable then
      pkgs
    else
      import pkgs.path {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };

  attr = "cudaPackages_" + lib.replaceStrings [ "." ] [ "_" ] cfg.version;
  cp =
    cudaSource.${attr} or (throw "aor.env.cuda.version = \"${cfg.version}\"：当前 nixpkgs 没有 ${attr}");

  # 每个库在 cudaPackages 里的包名。
  libraries = {
    cublas = cp.libcublas;
    cusparse = cp.libcusparse;
    cusolver = cp.libcusolver;
    curand = cp.libcurand;
    cufft = cp.libcufft;
    nvml = cp.cuda_nvml_dev;
    nvtx = cp.cuda_nvtx;
    nvrtc = cp.cuda_nvrtc;
    cupti = cp.cuda_cupti;
  };

  plugins = {
    cudnn = cp.cudnn;
    nccl = cp.nccl;
    nsight-systems = cp.nsight_systems;
    nsight-compute = cp.nsight_compute;
  };

  # 有拆分输出时，头文件取 include、库取 lib；没有拆分时就用整个包。
  headersOf = p: p.include or p.dev or p.out;
  libsOf = p: p.lib or p.out;

  core = [
    cp.cuda_nvcc
    cp.cuda_cudart
    (cp.cccl or cp.cuda_cccl)
  ]
  ++ lib.optional (cp ? cuda_crt) cp.cuda_crt
  ++ lib.optional (cp ? cuda_profiler_api) cp.cuda_profiler_api;

  selected = map (n: libraries.${n}) cfg.libraries;

  cudaHome = pkgs.symlinkJoin {
    name = "cuda-home-${cfg.version}";
    paths = core ++ map headersOf selected ++ lib.optionals buildable (map libsOf selected);
    # torch.utils.cpp_extension 链接时用 $CUDA_HOME/lib64。
    postBuild = ''
      if [ -d $out/lib ] && [ ! -e $out/lib64 ]; then ln -s lib $out/lib64; fi
    '';
  };

  # 宿主机驱动库：只软链驱动自身的几个库，不把整个系统库目录加进来（会混入宿主机 glibc）。
  # 每个候选目录一个子目录、按顺序进 LD_LIBRARY_PATH；宿主机上不存在的软链是悬空的，
  # 加载器会跳过——这样同一份求值结果在 NixOS 与 Ubuntu 上都成立，不必在求值期探测宿主机。
  driverLibs = pkgs.runCommand "cuda-host-driver" { } (
    lib.concatImapStrings (i: dir: ''
      mkdir -p $out/${toString i}
      for n in libcuda.so libcuda.so.1 libnvidia-ml.so.1 libnvidia-ptxjitcompiler.so.1 libnvidia-nvvm.so.4 libcudadebugger.so.1; do
        ln -s ${dir}/$n $out/${toString i}/$n
      done
    '') cfg.driverLibDirs
  );

  # 给 clang 系工具（clangd）的 CUDA 参数。nvcc 专用参数不在这里。
  clangCudaArgs = [
    "--cuda-path=${cudaHome}"
    "-nocudalib"
    "--no-cuda-version-check"
    "-Wno-unknown-cuda-version"
  ];

  # clang 看到的 host 侧头文件：显式给出宿主 gcc 的 libstdc++ 与 glibc，和 nvcc + gcc 构建时一致，
  # 也不依赖 clangd 包装器按 nix 的 cc-wrapper 补进来的那套（darwin 上是 libc++）。
  # darwin 上的 clang 不支持以 darwin 为 host 的 CUDA（device 端会吃进 Apple SDK 头文件而报错），
  # 所以分析模式下再让 clang 把 host 当成 x86_64-linux；这些头文件和 CUDA 头文件一样取自
  # x86_64-linux 包集合，只替换下载、不在本机构建。
  linuxGcc =
    (if cfg.hostCompiler != null then cudaSource."gcc${cfg.hostCompiler}" else cudaSource.gcc).cc;
  linuxTriple = cudaSource.stdenv.hostPlatform.config;
  clangHostArgs = lib.optional (!buildable) "--target=${linuxTriple}" ++ [
    "-nostdlibinc"
    "-isystem${linuxGcc}/include/c++/${linuxGcc.version}"
    "-isystem${linuxGcc}/include/c++/${linuxGcc.version}/${linuxTriple}"
    "-isystem${cudaSource.glibc.dev}/include"
    "-isystem${cudaSource.linuxHeaders}/include"
  ];
in
{
  options.aor.env.cuda = {
    enable = lib.mkEnableOption "CUDA 工具链";

    version = lib.mkOption {
      type = lib.types.str;
      example = "13.0";
      description = "CUDA 主.次版本，映射到 cudaPackages_X_Y。必填：它必须和 torch wheel 的 CUDA 版本对齐。";
    };

    archs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "9.0"
        "10.0"
      ];
      description = "目标 GPU 的 compute capability；导出为 TORCH_CUDA_ARCH_LIST。空表示交给构建系统决定。";
    };

    hostCompiler = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "11";
      description = "nvcc 宿主编译器的 gcc 主版本；非 null 时在构建平台上接管 CC / CXX。";
    };

    libraries = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames libraries));
      default = [ ];
      description = "并入 CUDA_HOME 的 CUDA 库（头文件；构建平台上另含库文件）。";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames plugins));
      default = [ ];
      description = "附加组件；只在构建平台上安装。";
    };

    driverLibDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/run/opengl-driver/lib" # NixOS
        "/usr/lib/${hostPlatform.parsed.cpu.name}-linux-gnu" # Debian / Ubuntu
      ];
      description = "按顺序查找宿主机 GPU 驱动库的目录（只在构建平台上使用）。";
    };

    buildable = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = buildable;
      description = "当前平台是否处于构建模式（能编译 CUDA 代码）；否则为分析模式。";
    };

    clangArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = clangHostArgs ++ clangCudaArgs;
      description = "clang 编译 CUDA 源文件所需的完整参数（自带标准库头文件路径），供 compile_commands 生成器使用；配合 aor.env.cpp.clangdSystemHeaders = false。";
    };

    clangHostArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = clangHostArgs;
      description = "clangArgs 里 host 侧的那部分（标准库头文件、分析模式下的目标替换），给同一项目里的普通 C++ 源文件用。";
    };

    home = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = cudaHome;
      description = "拼好的 CUDA_HOME。";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        env.CUDA_HOME = "${cudaHome}";
        env.CUDA_PATH = "${cudaHome}";
        env.CUDA_CLANG_ARGS = lib.concatStringsSep " " (clangHostArgs ++ clangCudaArgs);
        env.CUDA_CLANG_HOST_ARGS = lib.concatStringsSep " " clangHostArgs;
      }

      (lib.mkIf (cfg.archs != [ ]) {
        env.TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" cfg.archs;
      })

      (lib.mkIf buildable {
        packages = [ cudaHome ] ++ map (n: plugins.${n}) cfg.plugins;
        env.LD_LIBRARY_PATH = lib.concatStringsSep ":" (
          lib.imap1 (i: _: "${driverLibs}/${toString i}") cfg.driverLibDirs
        );
      })

      (lib.mkIf (buildable && cfg.hostCompiler != null) {
        # torch 的 cpp_extension 会把 $CC 作为 nvcc 的 -ccbin，CXX 编 .cpp，两者须是同一个 gcc：
        # 换掉整个 stdenv，CC / CXX 随之而来。
        stdenv = pkgs."gcc${cfg.hostCompiler}Stdenv";
      })
    ]
  );
}
