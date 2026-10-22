# Modular Dev Env：C/C++ 工具链（编译器 + 构建工具 + clangd）。
# 关掉它你会失去：项目内锁定版本的 C/C++ 编译器与 clangd。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.aor.env.cpp;
  inherit (pkgs.stdenv) hostPlatform;

  llvm =
    if cfg.compiler == "clang" && cfg.version != null then
      pkgs."llvmPackages_${cfg.version}"
    else
      pkgs.llvmPackages_latest;

  cc =
    if cfg.compiler == "clang" then
      llvm.clang
    else if cfg.version != null then
      pkgs."gcc${cfg.version}"
    else
      pkgs.gcc;

  stdenv =
    if cfg.compiler == "clang" then
      llvm.stdenv
    else if cfg.version != null then
      pkgs."gcc${cfg.version}Stdenv"
    else
      pkgs.gccStdenv;

  buildTools = {
    cmake = pkgs.cmake;
    ninja = pkgs.ninja;
    meson = pkgs.meson;
    make = pkgs.gnumake;
  };

  plugins = {
    ccache = pkgs.ccache;
    bear = pkgs.bear;
    valgrind = pkgs.valgrind;
    rr = pkgs.rr;
    gdb = pkgs.gdb;
    lldb = llvm.lldb;
  };

  # 插件在当前平台不可用时静默跳过。rr 的 meta.platforms 不准（见 trait/dev/lang/clang.nix），单独按平台判断。
  available =
    name: pkg:
    if name == "rr" then
      hostPlatform.system == "x86_64-linux"
    else
      lib.meta.availableOn hostPlatform pkg;
in
{
  options.aor.env.cpp = {
    enable = lib.mkEnableOption "C/C++ 工具链";

    compiler = lib.mkOption {
      type = lib.types.enum [
        "clang"
        "gcc"
      ];
      default = "clang";
      description = "CC / CXX 使用的编译器。";
    };

    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "19";
      description = "编译器主版本（映射到 llvmPackages_N / gccN）；null 取 nixpkgs 默认。";
    };

    buildTools = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames buildTools));
      default = [
        "cmake"
        "ninja"
      ];
      description = "要装的构建工具。";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames plugins));
      default = [ ];
      description = "附加工具组；当前平台不支持的会被跳过。";
    };

    clangdSystemHeaders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        是否让 nixpkgs 的 clangd 包装器自动补上本机 cc-wrapper 的系统头文件（CPATH）。
        compile commands 自带完整的标准库头文件路径时（例如 cuda 模块的 clangArgs）关掉，否则两套头文件会打架。
      '';
    };

    compileCommandsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "compile_commands.json 所在目录；非 null 时通过 CLANGD_FLAGS 告诉 clangd。";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      cc
      llvm.clang-tools # clangd / clang-format / clang-tidy
    ]
    ++ lib.optional (!cfg.clangdSystemHeaders) (
      lib.hiPrio (
        pkgs.writeShellScriptBin "clangd" ''exec ${llvm.clang-tools}/bin/clangd-unwrapped "$@"''
      )
    )
    ++ map (n: buildTools.${n}) cfg.buildTools
    ++ lib.filter (p: p != null) (
      map (n: if available n plugins.${n} then plugins.${n} else null) cfg.plugins
    );

    # CC / CXX 由 devenv 的 stdenv 决定（它在 shell 运行期导出，直接写 env.CC 会被覆盖）。
    # mkDefault：cuda 模块在构建平台上会换成 nvcc 的宿主 gcc。
    stdenv = lib.mkDefault stdenv;

    # 覆盖 Global Dev Env 的 --query-driver 设置：项目内的编译参数以本环境为准。
    env.CLANGD_FLAGS = lib.concatStringsSep " " (
      [ "--background-index" ]
      ++ lib.optional (cfg.compileCommandsDir != null) "--compile-commands-dir=${cfg.compileCommandsDir}"
    );
  };
}
