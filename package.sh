#!/usr/bin/env bash
# ============================================================
# package.sh — 把已安装前缀打包成「解压即用」tarball
#
# 用法:
#   ./package.sh --prefix <prefix> --out <dir> [--name <包名基名>]
#     --prefix  安装前缀（install.sh 的输出，含 lib/puxian 与 bin/）
#     --out     产物输出目录
#     --name    包名基名（默认 puxian-aarch64，输出 <name>.tar.gz）
#
# 产物: <out>/<name>.tar.gz（结构：bin/{px,pxc,...} + lib/puxian + README.md）
# 与手工打包同一套逻辑，CI 流水线直接调用。
# ============================================================
set -euo pipefail

PREFIX=""
OUT=""
NAME="puxian-aarch64"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done
[ -n "$PREFIX" ] && [ -d "$PREFIX/lib/puxian" ] || { echo "错误: 需要 --prefix <安装前缀>（含 lib/puxian）" >&2; exit 1; }
[ -n "$OUT" ] || { echo "错误: 需要 --out <输出目录>" >&2; exit 1; }

SELF="$(cd "$(dirname "$0")" && pwd)"
PKG="$OUT/pkg/$NAME"
rm -rf "$PKG"
mkdir -p "$PKG/bin" "$PKG/lib"

# 1) lib/puxian = 安装布局（含 native bootstrap、runtime、stdlib、tools/px）
cp -a "$PREFIX/lib/puxian/." "$PKG/lib/puxian/"
rm -rf "$PKG/lib/puxian/.rtcache"     # 清运行缓存，减小包体

# 2) bin/px = 自动定位 shim（readlink 相对解析，不硬编码路径）
cp "$SELF/px" "$PKG/bin/px"
chmod +x "$PKG/bin/px"

# 3) bin/* 相对符号链接
(cd "$PKG/bin" && for t in pxc pxc0 pxi pxl pxpar pxfmt pxlint pxdoc pxtest pxbench pxlsp pxmcp pxcheck; do
  ln -sf "../lib/puxian/bootstrap/$t" "./$t"
done)

# 4) 包内 README
cat > "$PKG/README.md" <<EOF
# PuXian aarch64 原生工具链（解压即用）

由 px-openEuler-bootstrap 自举产物打包：13 个静态零依赖 ELF +
官方发布包布局（runtime/ + stdlib/ + tools/px）。self-prove 通过
（编译器重编输出与 golden 逐字节一致）。

包名: $NAME

## 使用
    tar xzf $NAME.tar.gz
    export PATH="\$PWD/$NAME/bin:\$PATH"
    px --version
    px run  hello.px    # 解释执行
    px build hello.px   # 编译静态二进制 → ./build/hello（首次现编 runtime 缓存，需 gcc）

SHA-256 见发布页。仓库: github.com/banshanhanfu/px-openEuler-bootstrap
EOF

# 5) 打包 + SHA-256
mkdir -p "$OUT"
tar -czf "$OUT/$NAME.tar.gz" -C "$OUT/pkg" "$NAME"
echo "=== $OUT/$NAME.tar.gz ==="
ls -la "$OUT/$NAME.tar.gz"
sha256sum "$OUT/$NAME.tar.gz"