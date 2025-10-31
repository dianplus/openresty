# 本地测试指南

本目录包含的脚本可以在不提交到 GitHub 的情况下进行本地测试。

## 快速开始

### 1. 运行所有测试

```bash
cd .github/scripts
chmod +x test-scripts.sh
./test-scripts.sh
```

### 2. 测试特定脚本

```bash
./test-scripts.sh setup-runner
./test-scripts.sh configure-aliyun-cli
./test-scripts.sh find-cheapest-instance
```

## 测试方法

### 方法 1: 语法检查（推荐）

使用 `test-scripts.sh` 进行基础语法检查：

```bash
./test-scripts.sh all
```

这会检查：
- 脚本文件是否存在
- Bash 语法是否正确
- 函数定义是否合理

### 方法 2: ShellCheck 静态分析

使用 ShellCheck 进行深入的静态分析：

```bash
chmod +x run-shellcheck.sh
./run-shellcheck.sh
```

如果没有安装 ShellCheck，脚本会自动尝试安装。

### 方法 3: Workflow YAML 语法检查

检查 GitHub Actions workflow 文件的语法：

```bash
chmod +x test-workflow-syntax.sh
./test-workflow-syntax.sh
```

### 方法 4: 使用 act 本地运行（高级）

如果你想完整模拟 GitHub Actions 环境：

1. 安装 [act](https://github.com/nektos/act)：
   ```bash
   brew install act  # macOS
   # 或
   curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash  # Linux
   ```

2. 运行 workflow（需要设置 secrets）：
   ```bash
   cd ../../
   act workflow_dispatch -W .github/workflows/auto-amd64-build-clean.yml
   ```

### 方法 5: 手动测试脚本

#### 测试 configure-aliyun-cli.sh

```bash
export ALIYUN_REGION="cn-hangzhou"
export ALIYUN_ACCESS_KEY_ID="test-key"
export ALIYUN_ACCESS_KEY_SECRET="test-secret"

# 检查语法
bash -n configure-aliyun-cli.sh

# 查看帮助（会显示参数错误）
./configure-aliyun-cli.sh
```

#### 测试 find-cheapest-instance.sh

```bash
# 设置测试环境
export GITHUB_OUTPUT=$(mktemp)

# 如果安装了 spot-instance-advisor，可以实际运行
# 否则只能检查语法
bash -n find-cheapest-instance.sh
```

#### 测试 create-spot-instance.sh

```bash
# 检查语法
bash -n create-spot-instance.sh

# 查看参数要求
./create-spot-instance.sh
```

## 测试清单

在提交前，建议运行以下检查：

- [ ] `./test-scripts.sh all` - 所有脚本语法检查通过
- [ ] `./run-shellcheck.sh` - ShellCheck 检查通过
- [ ] `./test-workflow-syntax.sh` - Workflow YAML 语法正确
- [ ] 手动检查关键脚本的参数处理逻辑

## 注意事项

1. **不需要真实凭证**：语法检查和静态分析不需要真实的阿里云凭证
2. **需要真实环境的功能**：
   - `find-cheapest-instance.sh` 需要 `spot-instance-advisor` 工具
   - `create-spot-instance.sh` 需要配置好的 `aliyun` CLI
   - `wait-instance-ready.sh` 和 `cleanup-instance.sh` 需要真实的实例 ID

3. **mock 测试**：`test-helpers.sh` 提供了 mock 函数，可以在不需要真实环境的情况下测试脚本逻辑

## 持续集成

这些测试脚本也可以集成到 CI/CD 流程中，在每次提交时自动运行。

