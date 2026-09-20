#!/usr/bin/env bash
# ============================================================
# ci/bootstrap-aarch64.sh — 容器内完整流水线（自举→安装→打包→验证）
#
#   1) 解析上游 release → 定位发布包 + sha256sums.txt
#   2) 下载发布包并 SHA-256 校验 → 克隆同版本源码（tag 对齐，保自证通过）
#   3) bootstrap.sh 自举（golden→pxc0→自证→全工具链）→ install.sh 安装
#   4) package.sh 打包「解压即用」tarball → verify.sh 端到端验证
#
# 用法: bash ci/bootstrap-aarch64.sh <upstream_tag> [workdir]
# 示例: bash ci/bootstrap-aarch64.sh v0.2.0-m155 /work
# 依赖: gcc / git / curl / tar / python3 / file
#   - 容器内自动安装（apt-get / dnf / yum 三系都支持）
#   - 宿主环境直接跑（如 openEuler aarch64 原生已验证）
# ============================================================
set -euo pipefail
UPSTREAM_TAG="${1:?用法: ci/bootstrap-aarch64.sh <upstream_tag> [workdir]}"
WORK="${2:-/work}"
UPSTREAM_REPO=NanzhanGroup/PuXian
RELEASE_NAME="${UPSTREAM_TAG#v}"          # v0.2.0-m155 → 0.2.0-m155
cd "$WORK"

# 0. 容器依赖（宿主已具备时自动跳过；Ubuntu→apt，openEuler/RHEL→dnf/yum）
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq gcc git curl tar ca-certificates file python3 >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q gcc git curl tar ca-certificates file python3 >/dev/null
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q gcc git curl tar ca-certificates file python3 >/dev/null
fi

echo "== 1/5 解析上游 release: $UPSTREAM_REPO $UPSTREAM_TAG =="
python3 - "$UPSTREAM_REPO" "$UPSTREAM_TAG" > /tmp/rel-assets.txt <<'PY'
import json, sys, urllib.request
repo, tag = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", timeout=30) as r:
    data = json.load(r)
for a in data.get("assets", []):
    print(f"{a['name']}\t{a['browser_download_url']}")
PY
TGZ_URL="$(awk -F'\t' '$1 ~ /\.tar\.gz$/ {print $2}' /tmp/rel-assets.txt | head -1)"
SUMS_URL="$(awk -F'\t' '$1 == "sha256sums.txt" {print $2}' /tmp/rel-assets.txt | head -1)"
[ -n "$TGZ_URL" ] || { echo "错误: 上游 $UPSTREAM_TAG 未找到 .tar.gz 发布包资产" >&2; exit 1; }
echo "  发布包: ${TGZ_URL##*/}"

echo "== 2/5 下载并 SHA-256 校验 =="
mkdir -p dl
curl -fL --retry 3 -o dl/release.tar.gz "$TGZ_URL"
if [ -n "$SUMS_URL" ] && curl -fsL --max-time 30 -o dl/sha256sums.txt "$SUMS_URL"; then
  EXPECTED="$(grep -E '\.tar\.gz' dl/sha256sums.txt | head -1 | awk '{print $1}')"
  ACTUAL="$(sha256sum dl/release.tar.gz | awk '{print $1}')"
  if [ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "  SHA-256 OK: $ACTUAL"
  else
    echo "  SHA-256 校验失败（expected=$EXPECTED actual=$ACTUAL）" >&2
    exit 1
  fi
else
  echo "  上游未附 sha256sums.txt，跳过文件校验（自证仍会兜底）"
fi

echo "== 3/5 克隆同版本源码（tag=$UPSTREAM_TAG）=="
rm -rf src
clone_ok=0
for i in 1 2 3; do
  if git clone -q -c http.version=HTTP/1.1 --depth 1 --branch "$UPSTREAM_TAG" "https://github.com/$UPSTREAM_REPO.git" src; then
    clone_ok=1; break
  fi
  echo "  clone 失败（第 $i 次），2s 后重试"
  sleep 2
done
[ "$clone_ok" = 1 ] || { echo "错误: 克隆上游源码失败" >&2; exit 1; }

echo "== 4/5 自举 + 安装 + 打包 + 验证 =="
rm -rf build prefix
PX_SRC="$WORK/src" PX_RELEASE="$WORK/dl/release.tar.gz" PX_OUT="$WORK/build" \
  ./bootstrap.sh --install "$WORK/prefix"
./package.sh --prefix "$WORK/prefix" --out "$WORK" --name "puxian-aarch64-$RELEASE_NAME"
PATH="$WORK/prefix/bin:$PATH" ./verify.sh

echo "== 5/5 产物 =="
sha256sum "$WORK/puxian-aarch64-$RELEASE_NAME.tar.gz"
echo "CI OK"