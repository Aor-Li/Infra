# Modular Dev Env：CUTLASS / CuTe 头文件库 + CuTe DSL。
# 关掉它你会失去：锁定版本的 cutlass 头文件路径（给构建系统与 clangd），以及 DSL 的 editable 安装。
#
# 版本由 src 决定，三种来源：
#   - kernel 项目（默认）：devenv.yaml 里声明 `cutlass: { url: github:NVIDIA/cutlass/<rev>, flake: false }`，
#     src 自动取 inputs.cutlass，rev 锁在 Infra；
#   - 上游已 vendor 子模块的项目（flash-attention）：src 指向子模块，版本跟上游；
#   - cutlass 自己的 Project Dev Env：src = config.devenv.root。
# CuTe DSL 的 wheel（nvidia-cutlass-dsl）仍由项目的 pyproject 锁定；dsl 插件只负责把 src 里的 Python 层
# editable 地覆盖进去，并检查 wheel 版本与 src/python/CuTeDSL/requirements-cu13.txt 一致。
{
  config,
  lib,
  inputs ? { },
  ...
}:
let
  cfg = config.aor.env.cutlass;

  includeDirs = [
    "${cfg.src}/include"
    "${cfg.src}/tools/util/include"
  ];

  dslDir = "${cfg.src}/python/CuTeDSL";
  # 必须 --no-build-isolation：_editable_backend 在构建时按当前解释器的 platlib 找 wheel 里的 cutlass._mlir，
  # 隔离构建环境里算出来的是临时目录，装完 import 会找不到 cutlass._mlir。
  dslInstall = ''
    want=$(sed -n 's/^nvidia-cutlass-dsl\[cu13\]==//p' ${lib.escapeShellArg dslDir}/requirements-cu13.txt)
    have=$(python -c 'from importlib.metadata import version; print(version("nvidia-cutlass-dsl"))')
    if [ "$want" != "$have" ]; then
      echo "cutlass: venv 里的 nvidia-cutlass-dsl 是 $have，源码要求 $want：改项目 pyproject 后 uv lock" >&2
      exit 1
    fi
    uv pip install --no-build-isolation --no-deps -e ${lib.escapeShellArg dslDir}
  '';
in
{
  options.aor.env.cutlass = {
    enable = lib.mkEnableOption "CUTLASS 头文件库";

    src = lib.mkOption {
      type = lib.types.str;
      default =
        if inputs ? cutlass then
          inputs.cutlass.outPath
        else
          throw "aor.env.cutlass.src：devenv.yaml 里没有 cutlass input，须显式给出源码目录";
      defaultText = lib.literalExpression "inputs.cutlass.outPath";
      description = "cutlass 源码目录。默认取 devenv.yaml 里的 cutlass input；vendor 了子模块的项目指向子模块，cutlass 自己指向 config.devenv.root。";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "dsl" ]);
      default = [ ];
      description = "dsl：提供 cutlass:dsl-install 任务，把 src/python/CuTeDSL 以 editable 方式装进 venv（需要 aor.env.python）。";
    };

    includeDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = includeDirs;
      description = "头文件目录：cutlass / cute 本体与 tools/util。";
    };

    clangArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = map (d: "-I${d}") includeDirs;
      description = "includeDirs 对应的 -I 参数，供 compile_commands 生成器使用；同时以 CUTLASS_CLANG_ARGS 导出。";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        env.CUTLASS_PATH = cfg.src; # cutlass 自己的约定：Python 接口（cutlass_cppgen）与部分示例读它
        env.CUTLASS_CLANG_ARGS = lib.concatStringsSep " " cfg.clangArgs;
      }

      (lib.mkIf (lib.elem "dsl" cfg.plugins) {
        assertions = [
          {
            assertion = config.aor.env.python.enable;
            message = "aor.env.cutlass.plugins 含 dsl，需要 aor.env.python.enable = true";
          }
        ];
        tasks."cutlass:dsl-install" = {
          description = "以 editable 方式安装 CuTe DSL 的 Python 层（src/python/CuTeDSL，覆盖 wheel 里的 libs-core）";
          exec = dslInstall;
          # venv 的 PATH / VIRTUAL_ENV 由 devenv:python:uv 导出；单独 `devenv tasks run` 时没有它，python 会落到裸解释器
          after = [ "devenv:python:uv" ];
        };
      })
    ]
  );
}
