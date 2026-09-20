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
---

## 实战实录：方案 A 安装经验（aarch64 · 2026-09-20）

> 在 openEuler 22.03 LTS（aarch64）实测方案 A：下载 → SHA-256 校验 → 解压 → 进 PATH →
> `px --version` / `px run` / `px build` 全流程跑通（官方 `verify.sh` 输出 `VERIFY ALL PASS ✅`）。
> 以下为过程中遇到的具体问题、经验教训与语法要点，供后来者避坑。

### 本次遇到的问题

| # | 现象 | 原因 | 解决 |
|---|------|------|------|
| 1 | `px build` 报缺少编译器 | 宿主机没装 gcc；首次 build 要现编 runtime 缓存并调 gcc 静态链接 | 安装环境第一步先 `dnf install -y gcc`（Ubuntu/Debian 用 `apt install -y gcc`），再跑 `px build` |
| 2 | `px bench hello.px main` 报 `R1001：未定义变量 'main'` | bench 设计上会**剔除顶层 `def main`**（防解释器自动调用入口） | bench 目标函数用**无参的非 main 顶层函数** |
| 3 | `px bench toolchain_demo.px add` 报 `R1005：缺少参数 'a'` | bench 生成的是 `func()` 无参循环调用 | 目标函数必须**零参数**；有参函数先包一层无参 def |
| 4 | 向 `px mcp` / `px lsp` 发换行 JSON，**无任何输出** | jsonrpc_core 走 **Content-Length 帧**（`Content-Length: <字节数>\r\n\r\n<body>`，read(2)/write(2) 直通）；坏头会让服务器直接终止连接 | 按帧格式发送；body 字节数用 `wc -c` 取 UTF-8 长度 |
| 5 | 找不到编译产物 | `px build x.px` 输出在**源文件所在目录**的 `build/<name>`，不是当前目录 | 看编译成功打印的绝对路径；如 `px build /root/px-demo/hello.px` → `/root/px-demo/build/hello` |

### 经验教训

1. **gcc 是 `px build` 的硬依赖，不是可选项**：装环境第一步就装，别等编译报错。
2. **装完立刻跑 `./verify.sh`**：版本 / `px run` / `px build` + 产物运行，三连是最小验收闭环。
3. **二次 `px build` 是亚秒级**（实测 0.24s）：runtime 预编译缓存 `$PXC_HOME/.rtcache` 命中后只编 base.c + 链接；首次慢是正常的。
4. **13 个工具全静态零依赖**（`ldd` 显示 `not a dynamic executable`）：`pxc/pxi/pxl/pxfmt/pxlint/pxdoc/pxtest/pxbench/pxlsp/pxmcp/...` 拷到别的 aarch64 机器可直接跑；但**首次 build 仍需目标机有 gcc**。
5. **写 MCP/LSP 客户端先想对帧格式**：PuXian 的 jsonrpc_core 用 Content-Length 帧，不是 `\n` 分隔 JSON（见问题 4）。
6. **`bin/px` 是 shim**：自动定位包根；软链到 `/usr/local/bin` 后可全局使用，也可用 `PX_HOME` 覆盖。
7. **aarch64 方案 A 行为等价 `--cc gcc --no-quic`**：裁剪 QUIC 不影响 HTTP/WS/SQLite 等核心能力（README 原文）。

### 本次用到的 .px 语法要点

```python
def main():                    # 程序入口，解释执行自动调用
    let msg = "hello, 普贤\n"  # let = 不可变；var = 可变；类型可省略（渐进类型）
    print(msg |> to_upper())   # |> 管道：等价 to_upper(msg)

def test_add():                # 顶层 test_ 函数 = 测试用例
    assert(1 + 1 == 2, "add 基础")  # px test 自动发现并运行

# ## 开头的注释 = 文档注释，px doc 会提取生成 Markdown API 文档

def work():                    # 无参顶层函数，px bench 的目标写法
    var s = 0
    var i = 0
    while i < 100:             # 控制流 = Python 风格：缩进 + 冒号
        s = s + i
        i = i + 1
    return s
```

### 快速验收清单（一次跑通）

```bash
px --version && px run hello.px && px build hello.px && ./build/hello   # 官方三连
px fmt --check x.px && px lint x.px && px test x.px && px doc --output x.md x.px
# MCP：initialize + tools/list（8 工具：run/fmt/lint/test/bench/doc/ast/build）
# LSP：initialize（capabilities 含 completion/definition/hover/textDocumentSync）
```