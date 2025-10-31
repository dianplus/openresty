# Runner Registration Token 获取失败排查指南

## 错误信息

```
❌ Permission denied: GitHub token lacks required permissions
❌ API response: {"message":"Resource not accessible by integration","status":"403"}
```

## 原因分析

`GITHUB_TOKEN` 在某些情况下可能没有足够的权限来获取 runner registration token，即使设置了 `permissions: actions:write`。

## 解决方案

### 方案 1: 检查 Workflow Permissions（已配置）

确保 workflow 文件中设置了正确的权限：

```yaml
permissions:
  actions: write
  contents: read
```

**当前状态**: ✅ 已在 `auto-amd64-build.yml` 和 `auto-arm64-build.yml` 中配置

### 方案 2: 检查仓库 Actions 设置

1. 进入仓库 Settings > Actions > General
2. 检查 "Workflow permissions" 设置
3. 确保选择了 "Read and write permissions" 或至少允许 "Read and write permissions" for GITHUB_TOKEN

### 方案 3: 使用 Personal Access Token (PAT)（推荐）

如果 `GITHUB_TOKEN` 仍然无法工作，可以使用 Personal Access Token：

#### 步骤 1: 创建 PAT

1. 登录 GitHub，进入 Settings > Developer settings > Personal access tokens > Tokens (classic)
2. 点击 "Generate new token (classic)"
3. 设置名称，例如: "Runner Registration Token"
4. 选择过期时间
5. 勾选权限：
   - `repo` (完整仓库访问权限)
   - 或者至少 `admin:repo_hook` 和 `repo:status`
6. 生成并复制 token

#### 步骤 2: 添加为 Secret

1. 进入仓库 Settings > Secrets and variables > Actions
2. 点击 "New repository secret"
3. 名称: `RUNNER_REGISTRATION_PAT` (注意：不能以 `GITHUB_` 开头)
4. 值: 粘贴刚才复制的 PAT
5. 保存

#### 步骤 3: 修改 Workflow

修改 `auto-amd64-build.yml` 和 `auto-arm64-build.yml` 中的 `Get Runner Registration Token` 步骤：

```yaml
- name: Get Runner Registration Token
  id: get_token
  run: |
    chmod +x .github/scripts/get-runner-registration-token.py
    echo "Fetching registration token..."
    # Use PAT if available, otherwise fallback to GITHUB_TOKEN
    # Note: Secret names cannot start with GITHUB_
    TOKEN_TO_USE="${{ secrets.RUNNER_REGISTRATION_PAT || secrets.GITHUB_TOKEN }}"
    set +e
    REGISTRATION_TOKEN=$(python3 .github/scripts/get-runner-registration-token.py \
      "$TOKEN_TO_USE" \
      "dianplus" \
      "openresty" 2>&1)
    EXIT_CODE=$?
    set -e
    
    if [ $EXIT_CODE -ne 0 ]; then
      echo "❌ Failed to get registration token (exit code: $EXIT_CODE)"
      echo "Output:"
      echo "$REGISTRATION_TOKEN"
      exit 1
    fi
    
    TOKEN=$(echo "$REGISTRATION_TOKEN" | tail -1)
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "" ]; then
      echo "❌ Registration token is empty"
      echo "Full output:"
      echo "$REGISTRATION_TOKEN"
      exit 1
    fi
    
    echo "registration_token=$TOKEN" >> $GITHUB_OUTPUT
    echo "✓ Registration token obtained (hidden for security)"
```

### 方案 4: 使用 GitHub App Token（高级）

如果组织中有 GitHub App，可以使用 App token，它通常有更灵活的权限配置。

## 验证修复

运行 workflow 后，检查日志中是否出现：

```
✓ Registration token obtained (hidden for security)
```

如果仍然失败，检查：
1. PAT 是否正确添加到 Secrets（名称不能以 `GITHUB_` 开头）
2. PAT 是否过期
3. PAT 是否有正确的权限范围（需要 `repo` 权限）

## 相关文档

- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
- [Managing runner registration tokens](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners#registering-self-hosted-runners)
- [Creating a personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)

