# PuXian openEuler 部署（aarch64 源码自举）

在 **openEuler 22.03 LTS / aarch64** 上，从源码自举出 PuXian 原生工具链的可复现流程。

> 👉 只想快点用？看 [QUICKSTART.md](QUICKSTART.md)（新服务器 4 步，含发布包直链）。

```
发布包 runtime/  C源码 + aarch64 静态库
      │               │
      ▼               ▼
  runtime 对象  +  golden/compiler.c ──► pxc0（原生编译器）
      │                    ▲
      │             自证：pxc0 重编 compiler.px
      │             输出与 golden 逐字节一致（0.2.0-m155：16387 行）
      ▼
  pxc / pxi / pxl / pxpar / pxfmt / pxlint / pxdoc / pxtest / pxbench / pxlsp / pxmcp / pxcheck
      │
      ▼
  13 个静态零依赖单 ELF（~3.7–4.2 MB）
```

## 为什么需要自举

PuXian 官方安装通道只面向 x86_64：

- **RPM 安装器**：仅支持 x86_64 RHEL 系发行版；
- **发布包** `puxian-<ver>-<commit>.tar.gz`：`bootstrap/` 预编译二进制是 x86_64，aarch64 上直接执行会报 `Exec format error`。

但发布包里的 `runtime/` 同时带了 **x86_64 与 aarch64 的预编译静态库**（mbedtls/sqlite3/zlib 的 `lib-aarch64`、`sqlite3-aarch64.o` 等），配合仓库自带的 **`selfhost/golden/compiler.c`**（编译器当前 C 镜像），就能在 aarch64 上从零自举，且全程**无需 Rust 工具链**。

> 自证（self-prove）是这个流程的信任根基：用 `pxc0` 重新编译 `compiler.px`，输出必须与 golden `compiler.c` 逐字节一致——即"编译器能忠实地重新生成自己"，之后所有工具链产物都可信。

## 已验证环境

| 项 | 值 |
|---|---|
| OS | openEuler 22.03 LTS（aarch64） |
| 编译器 | gcc 10.3.1 / GNU ld 2.37 |
| 硬件 | 8 vCPU / 14 GiB（并行编译约 1 分钟） |
| PuXian | 0.2.0-m155（发布包 commit `52ad8a1`；源码 HEAD `3f9fcab` 自证 OK） |
| 产物 | 13 个静态零依赖 ELF（pxc/pxc0/pxi/pxl/pxpar/pxfmt/pxlint/pxdoc/pxtest/pxbench/pxlsp/pxmcp/pxcheck） |

## 快速开始（新服务器）

```bash
# 0. 依赖（openEuler 用 dnf；其他发行版对应包管理器）
sudo dnf install -y gcc git curl tar

# 1. 获取本仓库与 PuXian 发布包
git clone https://github.com/banshanhanfu/px-openEuler-bootstrap.git
cd px-openEuler-bootstrap
#    发布包获取（任一）：
#    - 国内镜像  https://soft.xiusoft.cn/puxian/releases/
#    - GitHub    https://github.com/NanzhanGroup/PuXian/releases
#    文件形如   puxian-0.2.0-m155-52ad8a1.tar.gz

# 2. 自举 + 安装（默认装到 ~/.local，也可 --install /opt/px）
PX_RELEASE=/path/to/puxian-0.2.0-m155-52ad8a1.tar.gz ./bootstrap.sh --install

# 3. 进 PATH 并验证
export PATH="$HOME/.local/bin:$PATH"
./verify.sh        # 版本 + px run + px build → VERIFY ALL PASS ✅
```

发布包也可直接给 URL：

```bash
PX_RELEASE=https://soft.xiusoft.cn/puxian/releases/puxian-0.2.0-m155-52ad8a1.tar.gz \
  ./bootstrap.sh --install
```

## 使用

```bash
px --version                    # px 0.2.0-m155
px run hello.px                 # 解释执行
px build hello.px               # 编译静态二进制 → ./build/hello
```

- 安装后 `px` 是官方 `tools/px` 包装器的薄封装（见仓库根 `px`），自动注入两处 aarch64 差异：**C 轨构建**（`PX_BUILD_ENGINE=c`）与**原生构建 flag**（`--cc gcc --no-quic` + aarch64 静态库）。
- 为什么不用 M71-S2 的 `--target aarch64`：它是**交叉编译**语义，强制要求 `aarch64-linux-musl-gcc`；原生 aarch64 机用低层 flag 组合（M57-S4）即可。
- 为什么默认 VM 字节码轨不行：VM 轨需要官方 x86_64 预编译的 `pxc_vm`，aarch64 无法执行。C 轨是官方逃生舱，产物与官方对拍契约一致（逐字节一致）。
- 底层工具可直调：`pxc build x.px`（输出 C 到 stdout）、`pxi x.px` 等，均在 `~/local/bin`。

## 部署原理（4 阶段）

| 阶段 | 做什么 | 产物 |
|---|---|---|
| 1 | 编译 runtime 对象（`-DPX_NO_QUIC`，19 个 C 文件，并行） | `rtobj/*.o` |
| 2 | `golden/compiler.c` + runtime 对象 + aarch64 静态库 → 静态链接 | `pxc0` |
| 3 | `pxc0 build selfhost/compiler.px`，与 golden 逐字节比较 | 自证结论 |
| 4 | 用 `pxc0` 自举编译 12 个工具 `.px` → C → gcc 静态链接 | 全套工具链 |

细节见 `bootstrap.sh`（每个 stage 都有注释与日志；中间产物在 `out/work/`）。

## 常见问题

**自证失败（SELF-PROVE DIFF）**
源码与发布包版本不匹配。发布包 `VERSION` 记录了版本（如 `0.2.0-m155`）；请用与发布包同版本的源码（`PX_SRC_REF=<commit>`），或换匹配的发布包。脚本默认在自证失败时退出，不会产出不可信工具链。

**链接时出现 `getaddrinfo` / `gethostbyname` warning**
glibc 静态链接的已知行为（运行解析需要目标机 glibc），不影响单机部署与产物正确性。

**`px build` 首次较慢**
官方 `tools/px` 有 runtime 预编译缓存（`$PXC_HOME/.rtcache`），首次按实际配置现编 runtime，后续亚秒级。

**我在 x86_64 机器上**
直接走官方 RPM/发布包即可，本仓库是 aarch64 专属路径。

**为什么裁剪 QUIC/H3（`-DPX_NO_QUIC`）**
aarch64 没有 ngtcp2/openssl-quictls 预编译静态库（官方只随包提供 x86_64 版）。裁剪后不影响 HTTP/WS/SQLite 等核心能力；`px build --full` 需要自备 aarch64 QUIC 库，不在本流程范围。

## 目录结构

```
bootstrap.sh   一键自举构建（4 阶段，见上表）
install.sh     安装：发布包布局 + 原生二进制 → prefix（默认 ~/.local）
px             入口 shim 模板（install.sh 会生成硬编码路径版到 $PREFIX/bin/px）
verify.sh      部署后验证（版本 / px run / px build / 运行产物）
out/           构建输出（gitignore）
```

## License

Apache-2.0。本仓库是部署脚本与文档；PuXian 语言本体见
[github.com/NanzhanGroup/PuXian](https://github.com/NanzhanGroup/PuXian)（Apache-2.0）。