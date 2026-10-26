"""为 cutlass 合成 clangd 用的 compile_commands.json（不需要先 cmake configure）。

覆盖 examples/ test/unit/ tools/ 下的 .cu / .cpp 源文件（头文件由 clangd 按最近的源文件推断）。
只翻译本仓库 CMakeLists 里的东西：include 路径、宏、C++ 标准；nvcc 专用参数
（--expt-relaxed-constexpr、-gencode、--options-file ...）一律不出现，clangd 才不会报不认识的参数。
clang 读 CUDA 的方言（头文件路径、nvcc 版本宏、macOS 上的 host 目标替换）由 cuda 模块通过
CUDA_CLANG_ARGS / CUDA_CLANG_HOST_ARGS 给出，cutlass 本体的 -I 由 cutlass 模块通过 CUTLASS_CLANG_ARGS 给出。

用法：python compdb.py <仓库根> <输出目录>   （由 Project Dev Env 的 cutlass:compdb task 调用）
环境：CUTLASS_NVCC_ARCHS（CMake 写法，如 "90a;100a"：决定默认的 --cuda-gpu-arch 与架构相关宏）、
      CUTLASS_GTEST_INCLUDE（test/unit 用的 gtest 头文件目录）。
"""

import json
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

# 与顶层 CMakeLists.txt 的默认值对齐；上游改了编译参数时同步这里。
CXX_STD = "-std=c++17"
COMMON_DEFINES = [
    "-DCUTLASS_ENABLE_TENSOR_CORE_MMA=1",
    "-DCUTLASS_DEBUG_TRACE_LEVEL=0",
    "-DCUTLASS_ENABLE_GDC_FOR_SM100=1",
    "-DCUTLASS_TEST_LEVEL=0",
]
TEST_DEFINES = ['-DCUTLASS_TARGET_NAME="clangd"']
SKIP_DIRS = {"python", "__pycache__", "build"}

# 文件路径里的架构线索 → clang 的 --cuda-gpu-arch。sm90 / sm100 系列要带 a 才有 wgmma / tcgen05。
ARCH_BY_HINT = [
    (re.compile(r"sm_?(\d{2,3})"), None),
    (re.compile(r"volta"), "sm_70"),
    (re.compile(r"turing"), "sm_75"),
    (re.compile(r"ampere"), "sm_80"),
    (re.compile(r"ada"), "sm_89"),
    (re.compile(r"hopper"), "sm_90a"),
    (re.compile(r"blackwell_geforce"), "sm_120a"),
    (re.compile(r"blackwell"), "sm_100a"),
]


def clang_arch(cmake_arch: str) -> str:
    """CMake 写法 "90a" / "100f" → "sm_90a" / "sm_100f"。"""
    return f"sm_{cmake_arch}"


def arch_for(path: str, default: str) -> str:
    p = path.lower()
    for pat, arch in ARCH_BY_HINT:
        m = pat.search(p)
        if not m:
            continue
        if arch is not None:
            return arch
        n = int(m.group(1))
        return f"sm_{n}a" if n >= 90 else f"sm_{n}"
    return default


def sources(d: Path):
    for p in sorted(d.rglob("*")):
        if p.suffix not in (".cu", ".cpp"):
            continue
        if SKIP_DIRS & set(p.relative_to(d).parts):
            continue
        yield p


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2])
    cuda_home = os.environ["CUDA_HOME"]
    if not (root / "include" / "cutlass" / "cutlass.h").is_file():
        sys.exit(f"compdb: {root} 不像 cutlass 仓库根")

    cmake_archs = [a for a in os.environ.get("CUTLASS_NVCC_ARCHS", "90a").split(";") if a]
    default_arch = clang_arch(cmake_archs[0])
    arch_defines = []
    if any(a.endswith("f") for a in cmake_archs):
        arch_defines.append("-DCUTLASS_SM100_FAMILY_ARCHS_ENABLED")

    # 全仓共用的 include：cutlass 模块给的本体 + tools/util，再加 tools/library 与 tools/profiler
    # （CMake 里按 target 分配，这里一并给出无妨）。
    common_inc = [
        *shlex.split(os.environ["CUTLASS_CLANG_ARGS"]),
        f"-I{root / 'tools' / 'library' / 'include'}",
        f"-I{root / 'tools' / 'profiler' / 'include'}",
    ]

    clang = shutil.which("clang++") or "clang++"

    # cuda 模块按平台给出 clang 参数（分析模式下含 host 目标替换），这里不做平台判断。
    cuda_clang = shlex.split(os.environ["CUDA_CLANG_ARGS"])
    host_clang = shlex.split(os.environ["CUDA_CLANG_HOST_ARGS"])
    # 普通 C++ 源文件看不到 --cuda-path，CUDA 头文件路径要显式给；cccl 子目录取 cuda 模块已经算好的那条。
    host_cuda_inc = [f"-isystem{cuda_home}/include", *[a for a in cuda_clang if a.startswith("-isystem")]]

    def entry(src: Path, extra: list[str]) -> dict:
        if src.suffix == ".cu":
            lang = ["-x", "cuda", f"--cuda-gpu-arch={arch_for(str(src.relative_to(root)), default_arch)}", *cuda_clang]
        else:
            # WITHOUT_CUDA 的测试（cute/core）由宿主编译器编译，但仍会 include CUDA 头文件（cuda_fp16.h 等）
            lang = ["-x", "c++", *host_clang, *host_cuda_inc]
        args = [clang, *lang, CXX_STD, *COMMON_DEFINES, *arch_defines, *extra, *common_inc, "-c", str(src)]
        return {"directory": str(root), "file": str(src), "arguments": args}

    entries = []

    examples = root / "examples"
    ex_inc = [f"-I{examples / 'common'}"]
    for src in sources(examples):
        entries.append(entry(src, ex_inc))

    unit = root / "test" / "unit"
    gtest = os.environ.get("CUTLASS_GTEST_INCLUDE")
    test_inc = [f"-I{unit}", f"-I{unit / 'common'}"] + ([f"-isystem{gtest}"] if gtest else [])
    for src in sources(unit):
        entries.append(entry(src, [*TEST_DEFINES, *test_inc]))

    for sub in ("library", "profiler"):
        for src in sources(root / "tools" / sub / "src"):
            entries.append(entry(src, []))

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "compile_commands.json"
    out.write_text(json.dumps(entries, indent=1))
    print(f"compdb: {len(entries)} 条 → {out}")


if __name__ == "__main__":
    main()
