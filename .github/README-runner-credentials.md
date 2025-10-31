# GitHub Actions Runner 凭据传递说明

## 凭据类型和用途

### 1. Registration Token（注册令牌）

**用途**: 用于将 self-hosted runner 注册到 GitHub 仓库或组织

**特点**:

- **临时性**: 通常有效期约 1 小时
- **一次性**: 每次注册 runner 时都需要新的 token
- **安全性**: 不能用于其他 GitHub API 操作

**获取方式**:

- 通过 GitHub API: `POST /repos/{owner}/{repo}/actions/runners/registration-token`
- 需要具有 `repo` 或 `admin:repo` 权限的 token

**在代码中的使用**:

```python
# Workflow 中动态获取
REGISTRATION_TOKEN=$(python3 .github/scripts/get-runner-registration-token.py \
  "${{ secrets.GITHUB_TOKEN }}" \
  "dianplus" \
  "openresty")

# 传递给 User Data 脚本
export GITHUB_TOKEN="{registration_token}"  # 注意：这里命名为 GITHUB_TOKEN 但实际是 registration token
```

### 2. GITHUB_TOKEN（工作流自动生成）

**用途**: GitHub Actions 工作流运行时的自动生成 token

**特点**:

- **自动生成**: 每次工作流运行时 GitHub 自动创建
- **临时性**: 仅在当前工作流运行期间有效
- **权限**: 默认具有 `actions:write` 和 `contents:read` 权限

**使用场景**:

- 获取 registration token（需要 `actions:write` 权限）
- 调用 GitHub API 查询 runner 状态 id
- 工作流内的其他 GitHub API 操作

**限制**:

- **不能直接用于 runner 注册**: `config.sh` 不接受普通的 `GITHUB_TOKEN`
- **需要 registration token**: 必须通过 API 获取 registration token

## 当前实现流程

### Workflow 执行流程

1. **获取 Registration Token**

   ```yaml
   - name: Get Runner Registration Token
     id: get_token
     run: |
       REGISTRATION_TOKEN=$(python3 .github/scripts/get-runner-registration-token.py \
         "${{ secrets.GITHUB_TOKEN }}" \
         "dianplus" \
         "openresty")
       echo "registration_token=$REGISTRATION_TOKEN" >> $GITHUB_OUTPUT
   ```

2. **创建 ECS 实例并传递 Token**

   ```yaml
   - name: Create Spot Instance
     run: |
       python3 .github/scripts/create-spot-instance.py \
         ... \
         "${{ steps.get_token.outputs.registration_token }}" \
         ...
   ```

3. **User Data 脚本接收并设置**

   ```bash
   # User Data 脚本中
   export GITHUB_TOKEN="{registration_token}"  # 实际是 registration token
   export RUNNER_NAME="{runner_name}-$(date +%s)"
   ```

4. **setup-runner.sh 使用 Token 注册**

   ```bash
   # setup-runner.sh 中
   ./config.sh --url "$github_url" \
     --token "$GITHUB_TOKEN" \  # 这里使用的是 registration token
     --name "$runner_name" \
     --labels "$runner_labels"
   ```

## 关键信息传递检查清单

### ✅ 已正确传递的信息

1. **Registration Token** ✅
   - 在 workflow 中动态获取
   - 通过 User Data 传递到实例
   - 由 `setup-runner.sh` 使用

2. **Runner 名称** ✅
   - 从 workflow env 传递: `RUNNER_NAME`
   - 在 User Data 中添加时间戳: `{runner_name}-$(date +%s)`

3. **架构信息** ✅
   - 传递到 User Data: `x64` 或 `arm64`
   - 用于下载正确的 runner 二进制文件

4. **Runner 标签** ✅
   - 在 `setup-runner.sh` 中自动生成:
     - `self-hosted,linux,AMD64` (x64)
     - `self-hosted,linux,ARM64` (arm64)

5. **GitHub 仓库 URL** ✅
   - 硬编码在 `setup-runner.sh` 中: `https://github.com/dianplus/openresty`

### ⚠️ 需要注意的问题

1. **Token 命名混淆**
   - User Data 中使用 `GITHUB_TOKEN` 环境变量名，但实际存储的是 registration token
   - 这是为了兼容 `setup-runner.sh` 的预期，但可能会造成混淆
   - **建议**: 考虑重命名为 `RUNNER_REGISTRATION_TOKEN` 以提高清晰度

2. **Registration Token 有效期**
   - Token 有效期约 1 小时
   - 如果实例启动时间超过 1 小时，token 可能失效
   - **当前处理**: Token 在实例创建时获取，应该足够快

3. **权限要求**
   - Workflow 需要 `actions:write` 权限来获取 registration token
   - 已在 workflow 中添加 `permissions` 配置

## 安全性考虑

1. **Token 不会暴露在日志中**
   - Registration token 不会打印到 workflow 日志
   - User Data 脚本中的 token 是 base64 编码的

2. **Token 有效期短**
   - Registration token 仅 1 小时有效
   - 注册后不再需要 token

3. **工作流中的 GITHUB_TOKEN**
   - 自动生成，仅在当前工作流运行期间有效
   - 不会持久化存储

## 故障排查

### Registration Token 获取失败

**错误**: `Permission denied: GitHub token lacks required permissions`

**原因**: `GITHUB_TOKEN` 没有 `actions:write` 权限

**解决**:

1. 确保 workflow 有 `permissions: actions:write`
2. 或者使用具有 `repo` 权限的 Personal Access Token (PAT)

### Runner 注册失败

**错误**: `Failed to configure runner`

**可能原因**:

1. Registration token 已过期（超过 1 小时）
2. Token 格式不正确
3. 网络连接问题

**排查步骤**:

1. 检查 `/var/log/github-runner/setup.log` 查看详细错误
2. 确认 token 是否在有效期内
3. 检查网络连接和代理设置

## 相关文件

- `.github/scripts/get-runner-registration-token.py` - 获取 registration token
- `.github/scripts/create-spot-instance.py` - 创建实例并生成 User Data
- `.github/scripts/setup-runner.sh` - Runner 设置脚本
- `.github/workflows/auto-amd64-build.yml` - AMD64 构建工作流
- `.github/workflows/auto-arm64-build.yml` - ARM64 构建工作流
