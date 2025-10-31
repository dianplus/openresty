# 快速测试指南

## 一键测试所有脚本

```bash
cd .github/scripts
./test-all.sh
```

## 分步测试

### 1. 测试脚本语法（最快，无需依赖）

```bash
cd .github/scripts
./test-scripts.sh all
```

这会检查所有脚本的 Bash 语法是否正确。

### 2. ShellCheck 静态分析（推荐）

```bash
cd .github/scripts
./run-shellcheck.sh
```

如果没有安装 ShellCheck，脚本会自动尝试安装。

### 3. 检查 Workflow YAML 语法

```bash
cd .github/scripts
./test-workflow-syntax.sh
```

如果没有安装 actionlint，脚本会自动尝试安装。

## 测试单个脚本

```bash
cd .github/scripts

# 测试特定脚本
./test-scripts.sh setup-runner
./test-scripts.sh configure-aliyun-cli
./test-scripts.sh find-cheapest-instance
./test-scripts.sh create-spot-instance
./test-scripts.sh wait-instance-ready
./test-scripts.sh cleanup-instance
```

## 手动语法检查

如果只想快速检查单个脚本的语法：

```bash
bash -n .github/scripts/setup-runner.sh
bash -n .github/scripts/configure-aliyun-cli.sh
# ... 等等
```

## 预期结果

✅ **成功示例**：

```log
=== GitHub Actions Scripts Test Suite ===

Testing configure-aliyun-cli.sh...
✓ Syntax check passed
✓ configure-aliyun-cli.sh test passed

Testing find-cheapest-instance.sh...
✓ Syntax check passed
✓ find-cheapest-instance.sh test passed

...

=== All tests passed ===
```

❌ **失败示例**：
如果脚本有语法错误，会显示具体的错误信息。

## 提示

- 这些测试**不需要真实的阿里云凭证**
- 这些测试**不需要提交到 GitHub**
- 可以在本地开发时随时运行
- 所有测试脚本都有错误处理，不会破坏你的环境
