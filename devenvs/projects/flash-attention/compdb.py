"""为 flash-attention 合成 clangd 用的 compile_commands.json（不需要先构建）。

只翻译 setup.py / hopper/setup.py 里的东西：include 路径、宏、C++ 标准；nvcc 专用参数
（--expt-*、-gencode、--threads ...）一律不出现，clangd 才不会报不认识的参数。
clang 读 CUDA 的方言（头文件路径、nvcc 版本宏、macOS 上的 host 目标替换）由 cuda 模块通过
CUDA_CLANG_ARGS / CUDA_CLANG_HOST_ARGS 给出，csrc/cutlass 的 -I 由 cutlass 模块通过 CUTLASS_CLANG_ARGS 给出。

用法：python compdb.py <仓库根> <输出目录>   （由 Project Dev Env 的 fa:compdb task 调用）
"""

import json
import os
import shlex
import shutil
import sys
import sysconfig
from pathlib import Path

# 与 setup.py 对齐的部分；上游改了编译参数时同步这里。
CXX_STD = "-std=c++17"  # torch < 2.13
TORCH_DEFINES = ["-DTORCH_API_INCLUDE_EXTENSION_H", "-D_GLIBCXX_USE_CXX11_ABI=1"]
FA2_CUDA_DEFINES = [
    "-U__CUDA_NO_HALF_OPERATORS__",
    "-U__CUDA_NO_HALF_CONVERSIONS__",
    "-U__CUDA_NO_HALF2_OPERATORS__",
    "-U__CUDA_NO_BFLOAT16_CONVERSIONS__",
]
FA3_DEFINES = [
    "-DCUTE_SM90_EXTENDED_MMA_SHAPES_ENABLED",
    "-DCUTLASS_ENABLE_GDC_FOR_SM90",
    "-DCUTLASS_DEBUG_TRACE_LEVEL=0",
    "-DNDEBUG",
]
# 文件名后缀 → clang 的 --cuda-gpu-arch
ARCH_BY_SUFFIX = {"_sm80.cu": "sm_80", "_sm90.cu": "sm_90a", "_sm100.cu": "sm_100a"}
DEFAULT_ARCH = "sm_90a"


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2])
    cuda_home = os.environ["CUDA_HOME"]

    purelib = Path(sysconfig.get_paths()["purelib"])
    torch_inc = purelib / "torch" / "include"
    if not torch_inc.is_dir():
        sys.exit(f"compdb: 找不到 torch 头文件 {torch_inc}（venv 还没同步？）")
    if not (Path(os.environ["CUTLASS_PATH"]) / "include" / "cutlass" / "cutlass.h").is_file():
        sys.exit("compdb: csrc/cutlass 子模块未初始化：git submodule update --init csrc/cutlass")

    # macOS 的 CPU wheel 缺这个 cmake 生成的头（Linux 的 CUDA wheel 里有）：按 pytorch 的
    # c10/cuda/impl/cuda_cmake_macros.h.in 补一份，放进 compdb 目录下的 shim。
    shim = out_dir / "shim"
    macros = Path("c10") / "cuda" / "impl" / "cuda_cmake_macros.h"
    shim_inc = []
    if not (torch_inc / macros).is_file():
        (shim / macros).parent.mkdir(parents=True, exist_ok=True)
        (shim / macros).write_text("#pragma once\n#define C10_CUDA_BUILD_SHARED_LIBS\n")
        shim_inc = [f"-isystem{shim}"]

    common_inc = [
        f"-isystem{torch_inc}",
        f"-isystem{torch_inc / 'torch' / 'csrc' / 'api' / 'include'}",
        f"-isystem{sysconfig.get_paths()['include']}",
        *shlex.split(os.environ["CUTLASS_CLANG_ARGS"]),
        *shim_inc,
    ]

    clang = shutil.which("clang++") or "clang++"

    # cuda 模块按平台给出 clang 参数（分析模式下含 host 目标替换），这里不做平台判断。
    cuda_clang = shlex.split(os.environ["CUDA_CLANG_ARGS"])
    host_clang = shlex.split(os.environ["CUDA_CLANG_HOST_ARGS"])

    def cuda_args(arch: str) -> list[str]:
        return ["-x", "cuda", f"--cuda-gpu-arch={arch}", *cuda_clang]

    def entry(src: Path, extra: list[str], ext_name: str) -> dict:
        if src.suffix == ".cu":
            arch = next((a for s, a in ARCH_BY_SUFFIX.items() if src.name.endswith(s)), DEFAULT_ARCH)
            lang = cuda_args(arch)
        else:
            # 普通 C++ 源文件看不到 --cuda-path，CUDA 头文件路径要显式给；cccl 子目录取 cuda 模块已经算好的那条。
            lang = ["-x", "c++", *host_clang, f"-isystem{cuda_home}/include", *[a for a in cuda_clang if a.startswith("-isystem")]]
        args = [clang, *lang, CXX_STD, *TORCH_DEFINES, f"-DTORCH_EXTENSION_NAME={ext_name}", *extra, *common_inc, "-c", str(src)]
        return {"directory": str(root), "file": str(src), "arguments": args}

    entries = []

    fa2 = root / "csrc" / "flash_attn"
    fa2_inc = [f"-I{fa2}", f"-I{fa2 / 'src'}"]
    for src in sorted([*fa2.glob("*.cpp"), *(fa2 / "src").glob("*.cu")]):
        entries.append(entry(src, [*FA2_CUDA_DEFINES, *fa2_inc], "flash_attn_2_cuda"))

    hopper = root / "hopper"
    fa3_inc = [f"-I{hopper}"]
    for src in sorted([*hopper.glob("*.cpp"), *hopper.glob("*.cu"), *(hopper / "instantiations").glob("*.cu")]):
        entries.append(entry(src, [*FA3_DEFINES, *fa3_inc], "_C"))

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "compile_commands.json"
    out.write_text(json.dumps(entries, indent=1))
    print(f"compdb: {len(entries)} 条 → {out}")


if __name__ == "__main__":
    main()
