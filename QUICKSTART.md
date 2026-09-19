# 快速开始：新服务器 4 步搭好 PuXian（openEuler / aarch64）

适用于 **openEuler 22.03 LTS（aarch64）** 及同类 aarch64 Linux（Debian/Ubuntu 把 `dnf` 换成 `apt`）。
全程约 2~3 分钟（下载 71MB 发布包 + 自举构建约 1 分钟），最终得到 13 个静态零依赖二进制。

**已验证版本**：PuXian `v0.2.0-m155`（发布包 commit `52ad8a1`，SHA-256 见下）。
上游已有更新版本（m156/m157），同一脚本按同样步骤即可，但以自证（self-prove）通过为准。

## 一条龙（复制到服务器终端执行）

```bash
# ① 依赖 + 拉取本仓库
sudo dnf install -y gcc git curl tar
git clone https://github.com/banshanhanfu/px-openEuler-bootstrap.git
cd px-openEuler-bootstrap

# ② 下载发布包并校验 SHA-256（上游 GitHub Releases 直链）
curl -fL -o puxian-0.2.0-m155-52ad8a1.tar.gz \
  https://github.com/NanzhanGroup/PuXian/releases/download/v0.2.0-m155/puxian-0.2.0-m155-52ad8a1.tar.gz
echo "d6ca19007cf1c04eaad3287fa7bf0ebe1bac076163a9543cd2ee6bfd834db575  puxian-0.2.0-m155-52ad8a1.tar.gz" | sha256sum -c -

# ③ 自举构建 + 安装到 ~/.local（约 1 分钟，8 核并行）
PX_RELEASE=./puxian-0.2.0-m155-52ad8a1.tar.gz ./bootstrap.sh --install

# ④ 进 PATH + 验证
export PATH="$HOME/.local/bin:$PATH"
./verify.sh
```

最后看到 **`VERIFY ALL PASS ✅`** 即完成（版本 / `px run` 解释执行 / `px build` 静态二进制全部通过）。

## 之后的使用

```bash
px --version
px run  hello.px          # 解释执行
px build hello.px         # 编译静态二进制 → ./build/hello（零依赖，可拷走单跑）
```

- 安装位置：`~/.local/bin/{px,pxc,pxi,...}`，包根 `~/.local/lib/puxian/`；
  想装到别处：`./bootstrap.sh --install /opt/px`。
- `px` 入口已自动注入 aarch64 原生差异（C 轨构建 + aarch64 静态库 + 裁剪 QUIC），
  不需要手动加参数。
- 换新版本 / 换发布包：改 ② 的 URL 与 SHA-256 即可（aarch64 库随发布包提供）。

## 出问题先看这

| 现象 | 说明 |
|---|---|
| `自证失败 SELF-PROVE DIFF` | 源码与发布包版本不匹配；换同版本源码（`PX_SRC_REF=<commit>`）或同版本发布包 |
| `Exec format error` | 用到了官方 x86_64 二进制（如 `pxc_vm`）；本仓库安装流程已自动规避 |
| `px build` 首次偏慢 | runtime 预编译缓存（`.rtcache`）首次现编，二次亚秒级 |
| 链接时 `getaddrinfo` warning | glibc 静态链接已知行为，不影响产物 |

更多原理排查见 [README.md](README.md)。