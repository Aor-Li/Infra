# 分析模式验收：clangd 零错误解析代表性 C++/CUDA 文件，basedpyright 能解析 DSL 示例用到的 torch。
# clangd --check 的诊断行形如 `E[时间] [诊断名] Line N: ...`；`E[...] tweak:` 只是重构建议的自检，不算。
# 用法：bash check-analysis.sh <仓库根> <compdb 目录>   （由 devenv test 调用）
set -eu
root="$1"
compdb="$2"
cd "$root"

fail=0
for f in \
  examples/cute/tutorial/sgemm_sm80.cu \
  examples/48_hopper_warp_specialized_gemm/48_hopper_warp_specialized_gemm.cu \
  test/unit/cute/core/composition.cpp \
  test/unit/gemm/device/sm90_gemm_f16_f16_f16_alignx_tensor_op_f32_warpspecialized.cu \
  tools/profiler/src/cutlass_profiler.cu; do
  log=$(clangd --compile-commands-dir="$compdb" --check="$f" 2>&1) || true
  if printf '%s\n' "$log" | grep -q '^E\[[^]]*\] \['; then
    echo "FAIL clangd: $f" >&2
    printf '%s\n' "$log" | grep '^E\[[^]]*\] \[' | head -20 >&2
    fail=1
  else
    echo "ok   clangd: $f"
  fi
done

# 只要求第三方依赖可解析；DSL 本体（cutlass 包）在分析模式下没有 wheel，不算失败。
basedpyright --pythonpath "$(command -v python)" --outputjson \
  examples/python/CuTeDSL/cute/hopper/kernel/grouped_gemm/grouped_gemm.py >"$compdb/pyright.json" || true
missing=$(python - "$compdb/pyright.json" <<'PY'
import json, re, sys
diags = json.load(open(sys.argv[1]))["generalDiagnostics"]
mods = {m for d in diags if d.get("rule") == "reportMissingImports"
        for m in re.findall(r'"([\w.]+)"', d["message"])}
print(" ".join(sorted(m for m in mods if m.split(".")[0] in {"torch"})))
PY
)
if [ -n "$missing" ]; then
  echo "FAIL basedpyright: 无法解析 $missing" >&2
  fail=1
else
  echo "ok   basedpyright: torch 可解析"
fi

exit "$fail"
