#!/bin/bash

# User Data 脚本 - 基础版本
# 用于 Spot Instance 初始化，安装 GitHub Actions Runner
# Docker 安装将在 workflow 中使用 Actions 完成
# 此脚本会在实例启动时自动执行

set -euo pipefail

# 记录日志
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== User Data Script Started ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 变量定义（通过环境变量或参数传递）
RUNNER_REGISTRATION_TOKEN="${RUNNER_REGISTRATION_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
RUNNER_NAME="${RUNNER_NAME:-}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_VERSION="${RUNNER_VERSION:-2.311.0}"  # 可配置的 Runner 版本，默认使用稳定版本

# 代理配置（可选）
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1,100.100.100.200,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,mirrors.tuna.tsinghua.edu.cn,mirrors.aliyun.com,.aliyun.com,.aliyuncs.com,.alicdn.com,.dianplus.cn,.dianjia.io,.taobao.com}"

# 实例自毁配置（必需）
# 使用实例角色（ECS Self-Destruct Role Name）获取权限进行实例自毁
ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME="${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME:-}"

# 验证必需参数
if [[ -z "${RUNNER_REGISTRATION_TOKEN}" ]]; then
  echo "Error: RUNNER_REGISTRATION_TOKEN is required" >&2
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  echo "Error: GITHUB_REPOSITORY is required" >&2
  exit 1
fi

if [[ -z "${RUNNER_NAME}" ]]; then
  echo "Error: RUNNER_NAME is required" >&2
  exit 1
fi

echo "Repository: ${GITHUB_REPOSITORY}"
echo "Runner Name: ${RUNNER_NAME}"
echo "Runner Labels: ${RUNNER_LABELS:-default}"

# 配置代理（必须在 Runner 注册之前完成）
echo "=== Configuring proxy ==="
if [[ -n "${HTTP_PROXY}" ]]; then
  echo "Setting HTTP_PROXY: ${HTTP_PROXY}"
  export HTTP_PROXY="${HTTP_PROXY}"
  echo "export HTTP_PROXY=\"${HTTP_PROXY}\"" >> /etc/environment
  # 同步设置小写变量，确保 curl 等工具生效
  export http_proxy="${HTTP_PROXY}"
  echo "export http_proxy=\"${HTTP_PROXY}\"" >> /etc/environment
fi

if [[ -n "${HTTPS_PROXY}" ]]; then
  echo "Setting HTTPS_PROXY: ${HTTPS_PROXY}"
  export HTTPS_PROXY="${HTTPS_PROXY}"
  echo "export HTTPS_PROXY=\"${HTTPS_PROXY}\"" >> /etc/environment
  # 同步设置小写变量，确保 curl 等工具生效
  export https_proxy="${HTTPS_PROXY}"
  echo "export https_proxy=\"${HTTPS_PROXY}\"" >> /etc/environment
fi

if [[ -n "${NO_PROXY}" ]]; then
  echo "Setting NO_PROXY: ${NO_PROXY}"
  export NO_PROXY="${NO_PROXY}"
  echo "export NO_PROXY=\"${NO_PROXY}\"" >> /etc/environment
  
  # 同时设置小写版本（某些工具使用小写）
  export no_proxy="${NO_PROXY}"
  echo "export no_proxy=\"${NO_PROXY}\"" >> /etc/environment
fi

if [[ -n "${HTTP_PROXY}" || -n "${HTTPS_PROXY}" ]]; then
  echo "Proxy configuration enabled"
else
  echo "Proxy configuration not provided, using direct connection"
fi

# 更新系统
echo "=== Updating system ==="
if command -v yum &> /dev/null; then
  # Alibaba Cloud Linux / CentOS / RHEL
  yum update -y
  yum install -y curl wget git
elif command -v apt-get &> /dev/null; then
  # Ubuntu / Debian
  apt-get update -y
  apt-get install -y curl wget git
else
  echo "Error: Unsupported package manager" >&2
  exit 1
fi

# 安装 GitHub Actions Runner
echo "=== Installing GitHub Actions Runner ==="
RUNNER_DIR="/opt/actions-runner"
mkdir -p "${RUNNER_DIR}"

# 检测架构
ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" ]]; then
  RUNNER_ARCH="x64"
elif [[ "${ARCH}" == "aarch64" ]]; then
  RUNNER_ARCH="arm64"
else
  echo "Error: Unsupported architecture: ${ARCH}" >&2
  exit 1
fi

# 下载 Runner
echo "Using Runner version: ${RUNNER_VERSION}"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

cd "${RUNNER_DIR}"
echo "Downloading runner from: ${RUNNER_URL}"
# 增加重试与超时，提升在代理/弱网环境的鲁棒性
curl -o runner.tar.gz -L \
  --retry 5 --retry-all-errors \
  --connect-timeout 10 --max-time 300 \
  "${RUNNER_URL}"
tar xzf runner.tar.gz
rm runner.tar.gz

echo "=== Installing runner dependencies ==="
# 安装 GitHub Actions Runner 依赖（.NET 运行时依赖等）
# 注意：脚本会自动根据系统选择 apt/yum 安装 libicu 等依赖
./bin/installdependencies.sh

# 配置 Runner（Ephemeral 模式）
echo "=== Configuring Runner ==="
# 允许以 root 身份运行 runner 配置
export RUNNER_ALLOW_RUNASROOT=1
./config.sh \
  --url "https://github.com/${GITHUB_REPOSITORY}" \
  --token "${RUNNER_REGISTRATION_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS:-self-hosted,Linux,${RUNNER_ARCH}}" \
  --ephemeral \
  --unattended \
  --replace

# 安装 Runner 服务（使用 root 用户）
echo "=== Installing Runner service ==="
echo "Writing runner environment file: ${RUNNER_DIR}/.env"
{
  echo "HTTP_PROXY=${HTTP_PROXY}"
  echo "HTTPS_PROXY=${HTTPS_PROXY}"
  echo "NO_PROXY=${NO_PROXY}"
  # Lowercase variants for tools that rely on them under systemd service
  echo "http_proxy=${HTTP_PROXY}"
  echo "https_proxy=${HTTPS_PROXY}"
  echo "no_proxy=${NO_PROXY}"
  # 配置 post-job hook（必须在服务启动前配置）
  echo "export ACTIONS_RUNNER_HOOK_POST_JOB=\"${RUNNER_DIR}/post-job-hook.sh\""
} > "${RUNNER_DIR}/.env"
chmod 600 "${RUNNER_DIR}/.env" || true
./svc.sh install root

# 启动 Runner 服务
echo "=== Starting Runner service ==="
./svc.sh start

# 设置实例自毁机制
echo "=== Setting up instance self-destruct mechanism ==="
SELF_DESTRUCT_SCRIPT="/usr/local/bin/self-destruct.sh"

# 创建自毁脚本
cat > "${SELF_DESTRUCT_SCRIPT}" << 'SELF_DESTRUCT_EOF'
#!/bin/bash

# 实例自毁脚本
# 在 Runner 退出后自动删除 ECS 实例
# 使用实例角色（RamRoleName）获取权限进行认证

set -euo pipefail

# 日志文件
LOG_FILE="/var/log/self-destruct.log"

# 记录日志函数
log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${LOG_FILE}"
}

log "=== Instance Self-Destruct Script Started ==="

# 获取实例 ID（通过阿里云元数据服务）
METADATA_URL="http://100.100.100.200/latest/meta-data"
INSTANCE_ID=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/instance-id" || echo "")
REGION_ID=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/region-id" || echo "")

if [[ -z "${INSTANCE_ID}" ]]; then
    log "Error: Failed to get instance ID from metadata service"
    exit 1
fi

if [[ -z "${REGION_ID}" ]]; then
    log "Error: Failed to get region ID from metadata service"
    exit 1
fi

log "Instance ID: ${INSTANCE_ID}"
log "Region ID: ${REGION_ID}"

# 检查 Aliyun CLI 是否已安装
if ! command -v aliyun &> /dev/null; then
    log "Error: Aliyun CLI is not installed"
    exit 1
fi

# 配置 Aliyun CLI 使用实例角色认证
# 获取实例角色名称（从元数据服务）
RAM_ROLE_NAME=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/ram/security-credentials/" || echo "")

if [[ -z "${RAM_ROLE_NAME}" ]]; then
    log "Error: Failed to get RAM role name from metadata service"
    log "Please ensure the instance has a RAM role attached"
    exit 1
fi

log "RAM Role Name: ${RAM_ROLE_NAME}"
log "Configuring Aliyun CLI to use instance role authentication"

# 配置 aliyun cli 使用实例角色认证
# 使用非交互式方式配置
aliyun configure set \
    --mode EcsRamRole \
    --ram-role-name "${RAM_ROLE_NAME}" \
    --region "${REGION_ID}" 2>&1 | tee -a "${LOG_FILE}" || {
    log "Error: Failed to configure Aliyun CLI"
    exit 1
}

log "Aliyun CLI configured successfully"

# 等待一段时间，确保 Runner 完全退出
log "Waiting 10 seconds before self-destruct..."
sleep 10

# 删除实例
log "Deleting instance: ${INSTANCE_ID}"
RESPONSE=$(aliyun ecs DeleteInstance \
    --RegionId "${REGION_ID}" \
    --InstanceId "${INSTANCE_ID}" \
    --Force true 2>&1)

EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]]; then
    log "Error: Failed to delete instance (exit code: ${EXIT_CODE})"
    log "Response: ${RESPONSE}"
    exit ${EXIT_CODE}
fi

log "Instance deleted successfully: ${INSTANCE_ID}"
log "=== Instance Self-Destruct Script Completed ==="
SELF_DESTRUCT_EOF

chmod +x "${SELF_DESTRUCT_SCRIPT}"

# 验证实例角色配置
if [[ -z "${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME:-}" ]]; then
    echo "Warning: ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME is not configured, self-destruct mechanism may not work"
    echo "Please configure ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME in GitHub Variables"
else
    echo "Using instance role (${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}) for self-destruct mechanism"
fi

# 创建 systemd service，在 Runner 服务停止后执行自毁脚本
echo "=== Creating self-destruct systemd service ==="
# 使用 Runner 的 post-job hook 更可靠
# 创建 post-job hook 脚本（必须在 Runner 服务启动前创建）
cat > "${RUNNER_DIR}/post-job-hook.sh" << 'HOOK_EOF'
#!/bin/bash
# Runner post-job hook
# 在 Job 完成后执行实例自毁
/usr/local/bin/self-destruct.sh
HOOK_EOF

chmod +x "${RUNNER_DIR}/post-job-hook.sh"

# 注意：post-job hook 的环境变量已经在 .env 文件中配置（在 Runner 服务启动前）

# 同时创建 systemd service 作为备用机制
cat > /etc/systemd/system/self-destruct.service << 'SERVICE_EOF'
[Unit]
Description=Instance Self-Destruct Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# 等待 Runner 服务停止后执行自毁脚本
ExecStart=/bin/bash -c 'while systemctl is-active --quiet actions.runner.*.service 2>/dev/null; do sleep 5; done; /usr/local/bin/self-destruct.sh'
StandardOutput=journal
StandardError=journal
EnvironmentFile=/etc/environment

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 启用并启动服务（作为备用机制）
systemctl daemon-reload
systemctl enable self-destruct.service
systemctl start self-destruct.service

echo "Self-destruct service created, enabled and started"
echo "Post-job hook configured at ${RUNNER_DIR}/post-job-hook.sh"
echo "Instance will be automatically deleted when Runner service stops or job completes"

echo "=== User Data Script Completed ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

