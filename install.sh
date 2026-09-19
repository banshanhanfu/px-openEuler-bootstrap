#!/usr/bin/env bash
# ============================================================
# install.sh — 把自举出的原生工具链安装成可直接使用的 `px`
#
# 布局（默认 prefix=~/.local）：
#   $PREFIX/lib/puxian/       官方发布包布局（runtime/ + stdlib/ + tools/px + VERSION）
#       └─ bootstrap/         替换为原生 aarch64 二进制（自举产物），移除 x86_64 预编译
#   $PREFIX/bin/px            入口 shim（自动注入 aarch64 原生参数）
#   $PREFIX/bin/pxc pxi ...   原生二进制直链（可用于底层调试）
#
# 用法：
#   ./install.sh --prefix <dir> --native <pxnative_dir> --release <release_root>
#   或由 bootstrap.sh --install [prefix] 自动调用
# ============================================================
set -euo pipefail

PREFIX="${HOME}/.local"
NATIVE=""
REL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --native) NATIVE="$2"; shift 2 ;;
    --release) REL="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

[ -n "$NATIVE" ] && [ -d "$NATIVE" ] || { echo "错误: 需要 --native <pxnative目录>" >&2; exit 1; }
[ -n "$REL" ] && [ -d "$REL" ] || { echo "错误: 需要 --release <发布包根目录>" >&2; exit 1; }

DEST="$PREFIX/lib/puxian"
BIN="$PREFIX/bin"
mkdir -p "$DEST" "$BIN"

# 1) 复制发布包布局（runtime/stdlib/tools/VERSION/LICENSE），bootstrap/ 换成原生二进制
rm -rf "$DEST"
cp -a "$REL" "$DEST"
for t in pxc pxi pxl pxpar pxfmt pxlint pxdoc pxtest pxbench pxlsp pxmcp pxcheck pxc0; do
  cp -f "$NATIVE/$t" "$DEST/bootstrap/$t"
done
# 官方 bootstrap/ 里的 pxc_vm / pxi_vm 是 x86_64 预编译，aarch64 跑不了，移除以免误用
rm -f "$DEST/bootstrap/pxc_vm" "$DEST/bootstrap/pxi_vm"

# 2) 安装 px shim（硬编码包根路径 + aarch64 原生参数注入）
cat > "$BIN/px" <<EOF
#!/usr/bin/env bash
# 原生 aarch64 px 入口（px-openEuler-bootstrap）
# 注入 aarch64 原生差异：
#   1) PX_BUILD_ENGINE=c —— 默认 VM 字节码轨需要官方 x86_64 预编译的 pxc_vm，
#      aarch64 无法执行；C 轨（逃生舱）产物与官方对拍契约一致
#   2) build 低层 flag —— 原生 gcc + aarch64 静态库 + 裁剪 QUIC
#      （--target aarch64 是交叉编译语义，强制 musl 交叉编译器，不使用）
set -u
export PX_HOME="$DEST"
export PX_BUILD_ENGINE=c
RT="$DEST/runtime"
if [ "\${1:-}" = "build" ]; then
  exec "$DEST/tools/px" build --cc gcc --no-quic --mbedtls-lib "\$RT/mbedtls/lib-aarch64" --sqlite-obj "\$RT/third_party/sqlite3/sqlite3-aarch64.o" --zlib-lib "\$RT/third_party/zlib/lib-aarch64" "\${@:2}"
fi
exec "$DEST/tools/px" "\$@"
EOF
chmod +x "$BIN/px"

# 3) 原生二进制直链
for t in pxc pxi pxl pxpar pxfmt pxlint pxdoc pxtest pxbench pxlsp pxmcp pxcheck pxc0; do
  ln -sf "$NATIVE/$t" "$BIN/$t"
done

echo "已安装:"
echo "  px    -> $BIN/px"
echo "  pxc.. -> $BIN/{pxc,pxi,pxl,pxpar,pxfmt,pxlint,pxdoc,pxtest,pxbench,pxlsp,pxmcp,pxcheck,pxc0}"
echo "  包根  -> $DEST"
echo "请确保 $BIN 在 PATH 中，然后运行 ./verify.sh"