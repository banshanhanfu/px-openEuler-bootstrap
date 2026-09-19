# 预构建二进制包（跳过自举）

此分支存放 **解压即用** 的原生 aarch64 工具链包（免去源码自举，约 1 分钟下载，解压即用）。

| 文件 | 版本 | SHA-256 |
|---|---|---|
| puxian-aarch64-0.2.0-m155.tar.gz | PuXian 0.2.0-m155 · aarch64 | def184b6a5161ee6afabaa3984e971867a2311426dcaec36efa2948a5e53a705 |

```bash
curl -fL -o puxian-aarch64-0.2.0-m155.tar.gz \
  https://raw.githubusercontent.com/banshanhanfu/px-openEuler-bootstrap/download/puxian-aarch64-0.2.0-m155.tar.gz
echo "def184b6a5161ee6afabaa3984e971867a2311426dcaec36efa2948a5e53a705  puxian-aarch64-0.2.0-m155.tar.gz" | sha256sum -c -
tar xzf puxian-aarch64-0.2.0-m155.tar.gz
export PATH="$PWD/puxian-aarch64-0.2.0-m155/bin:$PATH"
px --version
```

来源：`px-openEuler-bootstrap` 仓库自举产物（self-prove 16387 行逐字节一致），打包验证通过。
