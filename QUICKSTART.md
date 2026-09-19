# 快速开始：新服务器搭好 PuXian（openEuler / aarch64）

适用于 **openEuler 22.03 LTS（aarch64）** 及同类 aarch64 Linux（Debian/Ubuntu 把 `dnf` 换成 `apt`）。
已验证版本：PuXian `v0.2.0-m155`（发布包 commit `52ad8a1`）。

**两条路任选**：
- **方案 A（最快）**：下载预构建包，**解压即用**（37.6MB，1 分钟）。
- **方案 B（源码自举）**：从 golden 编译器自举，产出可信二进制（约 2~3 分钟）。

---

## 方案 A：下载解压即用（推荐）

```bash
# ① 下载并校验（来自本仓库 download 分支，SHA-256 与 Release 页一致）
curl -fL -o puxian-aarch64-0.2.0-m155.tar.gz \
  https://raw.githubusercontent.com/banshanhanfu/px-openEuler-bootstrap/download/puxian-aarch64-0.2.0-m155.tar.gz
echo "def184b6a5161ee6afabaa3984e971867a2311426dcaec36efa2948a5e53a705  puxian-aarch64-0.2.0-m155.tar.gz" | sha256sum -c -

# ② 解压 + 进 PATH
tar xzf puxian-aarch64-0.2.0-m155.tar.gz
export PATH="$PWD/puxian-aarch64-0.2.0-m155/bin:$PATH"

# ③ 验证
px --version
```

`px run` / `px build` 直接用。二进制来源：本仓库自举产物（self-prove 16387 行逐字节一致），
内容含官方发布包布局（runtime + stdlib）。Release 页：
https://github.com/banshanhanfu/px-openEuler-bootstrap/releases/tag/aarch64-0.2.0-m155

> 首次 `px build` 要现编 runtime 缓存，需要 `gcc`；之后亚秒级。

## 方案 B：从源码自举（官方公平起点，可验证信任）

```bash
# ① 依赖 + 拉取本仓库
sudo dnf install -y gcc git curl tar
git clone https://github.com/banshanhanfu/px-openEuler-bootstrap.git
cd px-openEuler-bootstrap

# ② 下载官方发布包并校验 SHA-256（上游 GitHub Releases 直链）
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

---

## 之后的使用

```bash
px --version
px run  hello.px          # 解释执行
px build hello.px         # 编译静态二进制 → ./build/hello（零依赖，可拷走单跑）
```

- 方案 A 装在解压目录；方案 B 默认 `~/.local/`（`./bootstrap.sh --install /opt/px` 可换）。
- `px` 入口已自动注入 aarch64 原生差异（C 轨构建 + aarch64 静态库 + 裁剪 QUIC），不需要手动加参数。
- 发布包升级：方案 A 等新包；方案 B 改 ② 的 URL/SHA 即可（aarch64 库随官方发布包提供）。

## 出问题先看这

| 现象 | 说明 |
|---|---|
| `自证失败 SELF-PROVE DIFF` | 源码与发布包版本不匹配；换同版本源码（`PX_SRC_REF=<commit>`）或同版本发布包 |
| `Exec format error` | 用到了官方 x86_64 二进制（如 `pxc_vm`）；本仓库安装流程已自动规避 |
| `px build` 首次偏慢 | runtime 预编译缓存（`.rtcache`）首次现编，二次亚秒级 |
| 链接时 `getaddrinfo` warning | glibc 静态链接已知行为，不影响产物 |

更多原理排查见 [README.md](README.md)。