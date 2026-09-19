#!/usr/bin/env bash
# ============================================================
# verify.sh — 部署后验证
#   1) px --version
#   2) px run（解释执行）
#   3) px build → 静态二进制 → 运行
# 全部通过输出 "VERIFY ALL PASS"，任一失败 exit 非 0。
# ============================================================
set -euo pipefail
PX="${PX:-px}"
command -v "$PX" >/dev/null 2>&1 || { echo "错误: 找不到 px（请先运行 bootstrap.sh --install 并确认 PATH）" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/hello.px" <<'EOF'
def main():
    let msg = "hello, 普贤\n"
    print(msg |> to_upper())
EOF

echo "== 1) 版本 =="
"$PX" --version || { echo "FAIL: --version" >&2; exit 1; }

echo "== 2) 解释执行 (px run) =="
OUT_RUN="$("$PX" run "$TMP/hello.px")"
echo "  run 输出: $OUT_RUN"
[ "$OUT_RUN" = "HELLO, 普贤" ] || { echo "FAIL: run 输出不符" >&2; exit 1; }

echo "== 3) 编译静态二进制 (px build) =="
cd "$TMP"
"$PX" build "$TMP/hello.px" || { echo "FAIL: build" >&2; exit 1; }
OUT_BIN="$("$TMP/build/hello")"
echo "  bin 输出: $OUT_BIN"
[ "$OUT_BIN" = "HELLO, 普贤" ] || { echo "FAIL: 二进制输出不符" >&2; exit 1; }
file "$TMP/build/hello" | sed 's/^/  /'

echo ""
echo "VERIFY ALL PASS ✅"