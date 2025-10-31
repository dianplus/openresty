# Runner 制备流程和日志查看指南

## Runner 制备流程

当 ECS 实例创建成功后，runner 的制备过程如下：

### 1. Cloud-init 执行 User Data 脚本
- **执行机制**: 阿里云 ECS 使用 **cloud-init** 来执行 User Data 脚本
- **脚本位置**: User Data 通过 `--UserData` 参数传递给 `aliyun ecs RunInstances`，cloud-init 会在实例首次启动时执行
- **Cloud-init 日志文件**:
  - `/var/log/cloud-init.log` - cloud-init 执行日志
  - `/var/log/cloud-init-output.log` - User Data 脚本的标准输出（如果 cloud-init 配置了输出重定向）
  - `/var/lib/cloud/instances/<instance-id>/user-data.txt` - User Data 脚本的原始内容
- **自定义日志文件**: `/var/log/user-data.log`（我们脚本自己创建的）
- **执行内容**:
  1. 设置环境变量（GITHUB_TOKEN, RUNNER_NAME）
  2. 下载 `setup-runner.sh` 脚本
  3. 执行 `setup-runner.sh`

### 2. Setup Runner 脚本执行
- **脚本位置**: `.github/scripts/setup-runner.sh`
- **来源**: 从 GitHub 仓库下载: `https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/setup-runner.sh`
- **日志文件**: `/var/log/github-runner/setup.log`
- **执行步骤**:
  1. 配置代理设置（HTTP_PROXY, HTTPS_PROXY, NO_PROXY）
  2. 更新系统并安装依赖（docker, git, curl, wget, jq）
  3. 获取 GitHub Actions Runner 最新版本
  4. 下载对应架构的 Runner 二进制文件
  5. 配置 Runner（连接到 GitHub 仓库）
  6. 启动 Runner 服务

### 3. Runner 服务运行
- **日志文件**: `/var/log/github-runner/runner.log`
- **PID 文件**: `/var/log/github-runner/runner.pid`
- **状态**: Runner 进程以后台方式运行，连接到 GitHub Actions

## 日志文件位置

所有日志文件都在 ECS 实例上：

### Cloud-init 相关日志
```
/var/log/cloud-init.log                   # cloud-init 主日志
/var/log/cloud-init-output.log            # User Data 脚本输出（如果启用）
/var/lib/cloud/instances/<instance-id>/user-data.txt  # User Data 原始内容
```

### 应用层日志
```
/var/log/user-data.log                    # User Data 脚本执行日志（我们自定义的）
/var/log/github-runner/setup.log          # Setup Runner 脚本执行日志
/var/log/github-runner/runner.log         # Runner 运行日志
/var/log/github-runner/runner.pid         # Runner 进程 ID
```

**注意**: 如果 `/var/log/user-data.log` 不存在或为空，请检查 `/var/log/cloud-init-output.log` 或 `/var/log/cloud-init.log` 来查看 cloud-init 的执行情况。

## 如何查看日志

### 方法 1: 使用 check-runner-status.py 脚本

检查 runner 状态和获取日志位置信息：

```bash
python3 .github/scripts/check-runner-status.py <instance-id>
```

这个脚本会显示：
- 实例状态和基本信息
- GitHub Runner 注册状态
- 日志文件位置
- SSH 连接指令（如果有公网 IP）

### 方法 2: SSH 到实例（如果有公网 IP）

```bash
# SSH 到实例
ssh root@<instance-public-ip>

# 查看 Cloud-init 日志（优先检查）
tail -f /var/log/cloud-init.log
tail -f /var/log/cloud-init-output.log

# 查看 User Data 原始内容
cat /var/lib/cloud/instances/*/user-data.txt

# 查看 User Data 日志（我们自定义的）
tail -f /var/log/user-data.log

# 查看 Setup 日志
tail -f /var/log/github-runner/setup.log

# 查看 Runner 日志
tail -f /var/log/github-runner/runner.log

# 检查 Runner 进程
ps aux | grep runner
cat /var/log/github-runner/runner.pid

# 检查 cloud-init 状态
cloud-init status
```

### 方法 3: 使用 Aliyun Cloud Assistant

如果实例没有公网 IP，可以使用 Aliyun Cloud Assistant：

```bash
# 检查 cloud-init 状态
aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'cloud-init status' \
  --Type RunShellScript

# 查看 Cloud-init 日志
aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'tail -100 /var/log/cloud-init.log' \
  --Type RunShellScript

aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'tail -100 /var/log/cloud-init-output.log' \
  --Type RunShellScript

# 查看 User Data 日志
aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'cat /var/log/user-data.log' \
  --Type RunShellScript

# 查看 Setup 日志
aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'tail -100 /var/log/github-runner/setup.log' \
  --Type RunShellScript

# 查看 Runner 日志
aliyun ecs InvokeCommand \
  --InstanceId <instance-id> \
  --CommandContent 'tail -100 /var/log/github-runner/runner.log' \
  --Type RunShellScript
```

### 方法 4: 通过 GitHub Actions API 检查

检查 runner 是否已注册到 GitHub：

```bash
# 需要设置 GITHUB_TOKEN 环境变量
export GITHUB_TOKEN=your_token

# 查看所有 runners
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/dianplus/openresty/actions/runners | jq

# 使用 check-runner-status.py（已包含此功能）
python3 .github/scripts/check-runner-status.py <instance-id>
```

## 监控 Runner 制备过程

### 在 GitHub Actions Workflow 中

Workflow 会自动执行以下步骤：

1. **Create Spot Instance**: 创建 ECS 实例
2. **Wait for Instance Ready**: 等待实例状态变为 Running
3. **Check Runner Status**: 检查 runner 状态（新增）

### 手动监控

使用 `wait-instance-ready.py` 脚本会显示：
- 实例状态变化
- 日志文件位置
- SSH 连接指令
- 使用 `check-runner-status.py` 的建议

## 常见问题排查

### Cloud-init 未执行 User Data

1. **检查 cloud-init 状态**:
   ```bash
   cloud-init status
   # 应该显示: status: done 或 status: running
   ```

2. **检查 cloud-init 日志**:
   ```bash
   tail -100 /var/log/cloud-init.log
   tail -100 /var/log/cloud-init-output.log
   ```

3. **检查 User Data 内容**:
   ```bash
   cat /var/lib/cloud/instances/*/user-data.txt
   ```

4. **确认镜像是否包含 cloud-init**:
   - 大多数阿里云官方镜像都包含 cloud-init
   - 如果使用自定义镜像，需要确保安装了 cloud-init

### Runner 未注册到 GitHub

1. 检查 `/var/log/cloud-init.log` 确认 cloud-init 是否成功执行
2. 检查 `/var/log/user-data.log` 确认 User Data 脚本是否执行成功
3. 检查 `/var/log/github-runner/setup.log` 确认 setup 脚本是否完成
4. 检查 `/var/log/github-runner/runner.log` 查看 runner 连接错误
5. 确认 GITHUB_TOKEN 是否有效

### Runner 进程启动失败

1. 检查 `/var/log/github-runner/runner.log` 查看错误信息
2. 检查 runner 配置文件: `/root/.runner`（如果存在）
3. 检查系统资源: `free -h`, `df -h`

### 网络连接问题

1. 检查代理配置: `echo $HTTP_PROXY $HTTPS_PROXY`
2. 测试网络连接: `curl -I https://github.com`
3. 检查 DNS: `nslookup github.com`

## 相关脚本

- `.github/scripts/create-spot-instance.py` - 创建 spot 实例并生成 user data
- `.github/scripts/setup-runner.sh` - Runner 制备脚本
- `.github/scripts/wait-instance-ready.py` - 等待实例就绪
- `.github/scripts/check-runner-status.py` - 检查 runner 状态
- `.github/scripts/view-runner-logs.py` - 查看日志（需要 SSH 或 Cloud Assistant）

