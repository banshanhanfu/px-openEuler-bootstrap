#!/usr/bin/env bash
# ============================================================
# bootstrap.sh — PuXian 原生 aarch64 工具链自举构建
#
# 适用：openEuler 22.03 LTS / aarch64（同类 aarch64 Linux 亦可）。
# 为什么需要它：官方 RPM 安装器仅支持 x86_64 RHEL 系，aarch64 上
#   PuXian 官方发布包内的 bootstrap/* 二进制均为 x86_64，无法直接执行。
#
# 策略（4 阶段）：
#   1. 用发布包 runtime/ 的 C 源码 + aarch64 预编译静态库，gcc 编译 runtime 对象
#   2. 用源码树 selfhost/golden/compiler.c（编译器当前 C 镜像）链接出原生 pxc0
#   3. 自证：pxc0 重编 selfhost/compiler.px，输出与 golden/compiler.c 逐字节一致
#      （0.2.0-m155：16387 行，byte-identical）
#   4. 用 pxc0 自举构建全工具链（pxc/pxi/pxl/pxpar/pxfmt/pxlint/pxdoc/
#      pxtest/pxbench/pxlsp/pxmcp/pxcheck），gcc 静态链接
#
# 用法：
#   PX_RELEASE=/path/to/puxian-<ver>-<commit>.tar.gz ./bootstrap.sh
#   PX_RELEASE=https://.../puxian-<ver>-<commit>.tar.gz ./bootstrap.sh
#   ./bootstrap.sh --install [prefix]    # 构建后安装（默认 prefix=~/.local）
#
# 可调环境变量：
#   PX_RELEASE   发布包路径或 URL（必填）。发布包可从
#                https://soft.xiusoft.cn/puxian/releases/  或
#                https://github.com/NanzhanGroup/PuXian/releases 获取，
#                文件名形如 puxian-<版本>-<commit>.tar.gz
#   PX_SRC       源码目录或 git URL（默认 https://github.com/NanzhanGroup/PuXian）
#   PX_SRC_REF   git 检出的 ref（默认远端默认分支；自证会校验与发布包匹配）
#   PX_OUT       构建输出目录（默认 $PWD/out）
#   PX_ALLOW_DIFF=1  自证不一致时仍继续（调试用，不推荐；发布请保持失败）
#
# 依赖：gcc、git（远程源码时）、curl（URL 发布包时）、tar
# ============================================================
set -euo pipefail
export LC_ALL=C LANG=C

# ---------- 参数解析 ----------
INSTALL=0
PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1; shift; if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then PREFIX="$1"; shift; fi ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（仅支持 --install [prefix]）" >&2; exit 1 ;;
  esac
done
[ -z "$PREFIX" ] && PREFIX="${HOME}/.local"

# ---------- 环境校验 ----------
ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
  echo "错误: 本脚本面向 aarch64（当前 $ARCH）。x86_64 请直接用官方 RPM/发布包。" >&2
  exit 1
fi
for c in gcc git tar; do command -v "$c" >/dev/null 2>&1 || { echo "错误: 缺少依赖 $c" >&2; exit 1; }; done

PX_RELEASE="${PX_RELEASE:-}"
if [ -z "$PX_RELEASE" ]; then
  echo "错误: 必须提供 PX_RELEASE（发布包路径或 URL）。" >&2
  echo "  获取：https://soft.xiusoft.cn/puxian/releases/ 或 GitHub Releases" >&2
  exit 1
fi

# ---------- 路径 ----------
OUT="${PX_OUT:-$PWD/out}"
WORK="$OUT/work"
REL=""                       # 解压后的发布包根目录
SRC="${PX_SRC:-https://github.com/NanzhanGroup/PuXian}"
SRC_REF="${PX_SRC_REF:-}"
NATIVE="$OUT/pxnative"
OBJ="$WORK/rtobj"
mkdir -p "$WORK" "$NATIVE" "$OBJ"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ---------- 0. 获取发布包 ----------
TGZ=""
case "$PX_RELEASE" in
  http://*|https://*)
    command -v curl >/dev/null 2>&1 || { echo "错误: URL 发布包需要 curl" >&2; exit 1; }
    TGZ="$WORK/$(basename "${PX_RELEASE%%\?*}")"
    if [ ! -f "$TGZ" ]; then
      log "下载发布包: $PX_RELEASE"
      curl -fL --retry 3 "$PX_RELEASE" -o "$TGZ"
    fi ;;
  *)
    [ -f "$PX_RELEASE" ] || { echo "错误: 找不到发布包文件 $PX_RELEASE" >&2; exit 1; }
    TGZ="$PX_RELEASE" ;;
esac

log "解压发布包: $TGZ"
tar xzf "$TGZ" -C "$WORK"
REL="$(find "$WORK" -maxdepth 1 -type d -name 'puxian-*' | head -1)"
[ -n "$REL" ] && [ -d "$REL/runtime" ] || { echo "错误: 发布包布局不符（缺 runtime/）" >&2; exit 1; }
log "发布包根目录: $REL"

# ---------- 0b. 获取源码树 ----------
if [ -d "$SRC/.git" ] || [ -d "$SRC/selfhost" ]; then
  log "使用已有源码目录: $SRC"
else
  log "克隆源码: $SRC"
  SRC="$WORK/src"
  if [ -n "$SRC_REF" ]; then
    git clone --depth 1 --branch "$SRC_REF" "$PX_SRC" "$SRC"
  else
    git clone --depth 1 "$PX_SRC" "$SRC"
  fi
fi
[ -f "$SRC/selfhost/golden/compiler.c" ] || { echo "错误: 源码树缺 selfhost/golden/compiler.c" >&2; exit 1; }
log "源码树: $SRC"

RT="$REL/runtime"

# ---------- stage 1: 编译 runtime 对象（aarch64，裁剪 QUIC） ----------
log "stage1: 编译 runtime 对象（-DPX_NO_QUIC，19 个）"
COMMON="-O2 -pthread -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DPX_NO_QUIC -I$RT -I$RT/third_party/miniz -I$RT/mbedtls/include -I$RT/third_party/sqlite3 -I$RT/third_party/zlib/include -I$RT/third_party/stb"
SRCS="runtime.c runtime_aes.c runtime_xml.c runtime_zip.c runtime_ws.c runtime_rsa.c runtime_sqlite.c runtime_route.c runtime_h2.c runtime_ffi.c runtime_zlib.c runtime_ed25519.c tweetnacl.c runtime_image.c vm.c coro.c"
PIDS=""
for f in $SRCS; do
  ( gcc -c $COMMON "$RT/$f" -o "$OBJ/$(basename "${f%.c}").o" ) &
  PIDS="$PIDS $!"
done
for f in miniz.c miniz_tinfl.c miniz_tdef.c; do
  ( gcc -c $COMMON "$RT/third_party/miniz/$f" -o "$OBJ/$(basename "${f%.c}").o" ) &
  PIDS="$PIDS $!"
done
for p in $PIDS; do wait "$p" || exit 1; done
echo "objects compiled: $(ls "$OBJ"/*.o | wc -l)"

# ---------- stage 2: 链接原生 pxc0（golden 编译器 C 镜像 + runtime） ----------
log "stage2: 链接原生 pxc0"
gcc -static -O2 -pthread -o "$NATIVE/pxc0" \
    -I"$RT" -I"$RT/third_party/miniz" -I"$RT/mbedtls/include" -I"$RT/third_party/sqlite3" -I"$RT/third_party/zlib/include" \
    "$SRC/selfhost/golden/compiler.c" \
    "$OBJ"/*.o \
    "$RT/third_party/sqlite3/sqlite3-aarch64.o" \
    "$RT/mbedtls/lib-aarch64/libmbedtls.a" "$RT/mbedtls/lib-aarch64/libmbedx509.a" "$RT/mbedtls/lib-aarch64/libmbedcrypto.a" \
    "$RT/third_party/zlib/lib-aarch64/libz.a" \
    -lm -ldl -lpthread
file "$NATIVE/pxc0" | sed 's/^/  /'
log "pxc0 built: $(stat -c %s "$NATIVE/pxc0") bytes"

# ---------- stage 3: 自证（byte-identical 校验） ----------
log "stage3: 自证（pxc0 build compiler.px vs golden）"
"$NATIVE/pxc0" build "$SRC/selfhost/compiler.px" > "$WORK/compiler-emitted.c" 2>"$WORK/compiler-emitted.err" || {
  echo "SELF-PROVE EMIT FAILED"; tail -20 "$WORK/compiler-emitted.err"; exit 1; }
if cmp -s "$WORK/compiler-emitted.c" "$SRC/selfhost/golden/compiler.c"; then
  log "自证 OK: 输出与 golden 逐字节一致（$(wc -l < "$WORK/compiler-emitted.c") 行）"
else
  if [ "${PX_ALLOW_DIFF:-0}" = "1" ]; then
    log "警告: 自证不一致，但 PX_ALLOW_DIFF=1，继续（结果不可信，仅供调试）"
  else
    echo "自证失败: 输出与 golden 不一致。" >&2
    echo "  原因通常是源码与发布包版本不匹配（发布包 VERSION=$(cat "$REL/VERSION" 2>/dev/null || echo '?')）。" >&2
    echo "  请用与发布包同版本的源码（PX_SRC_REF），或换匹配的发布包。" >&2
    exit 1
  fi
fi

# ---------- stage 4: 用 pxc0 自举构建全工具链 ----------
log "stage4: 构建工具链条目"
BUILD_ONE() {  # $1=name $2=pkg 内相对 src
  local name="$1" src="$2" o
  log "  build $name ($src)"
  if ! "$NATIVE/pxc0" build "$SRC/$src" > "$WORK/build-$name.c" 2>"$WORK/build-$name.err"; then
    echo "  FAIL emit $name"; tail -5 "$WORK/build-$name.err"; return 1; fi
  if ! gcc -c -O2 -I"$RT" -o "$WORK/build-$name.o" "$WORK/build-$name.c" 2>"$WORK/build-$name.cc.log"; then
    echo "  FAIL cc $name"; tail -10 "$WORK/build-$name.cc.log"; return 1; fi
  if ! gcc -static -O2 -pthread -o "$NATIVE/$name" "$WORK/build-$name.o" \
      "$OBJ"/*.o \
      "$RT/third_party/sqlite3/sqlite3-aarch64.o" \
      "$RT/mbedtls/lib-aarch64/libmbedtls.a" "$RT/mbedtls/lib-aarch64/libmbedx509.a" "$RT/mbedtls/lib-aarch64/libmbedcrypto.a" \
      "$RT/third_party/zlib/lib-aarch64/libz.a" \
      -lm -ldl -lpthread 2>"$WORK/build-$name.link.log"; then
    echo "  FAIL link $name"; tail -10 "$WORK/build-$name.link.log"; return 1; fi
  log "  OK $name（$(stat -c %s "$NATIVE/$name") bytes）"
}

BUILD_ONE pxc    selfhost/compiler.px
BUILD_ONE pxi    selfhost/interp.px
BUILD_ONE pxl    selfhost/lexer.px
BUILD_ONE pxpar  selfhost/parser.px
BUILD_ONE pxfmt  tools/pxfmt.px
BUILD_ONE pxlint tools/pxlint.px
BUILD_ONE pxdoc  tools/pxdoc.px
BUILD_ONE pxtest tools/pxtest.px
BUILD_ONE pxbench tools/pxbench.px
BUILD_ONE pxlsp  tools/pxlsp.px
BUILD_ONE pxmcp  tools/pxmcp.px
BUILD_ONE pxcheck tools/pxcheck.px

log "ALL DONE: $NATIVE"
ls -la "$NATIVE"

# ---------- 安装（可选） ----------
if [ "$INSTALL" = "1" ]; then
  ./install.sh --prefix "$PREFIX" --native "$NATIVE" --release "$REL"
fi