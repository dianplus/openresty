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
fi

if [[ -n "${HTTPS_PROXY}" ]]; then
  echo "Setting HTTPS_PROXY: ${HTTPS_PROXY}"
  export HTTPS_PROXY="${HTTPS_PROXY}"
  echo "export HTTPS_PROXY=\"${HTTPS_PROXY}\"" >> /etc/environment
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
curl -o runner.tar.gz -L "${RUNNER_URL}"
tar xzf runner.tar.gz
rm runner.tar.gz

# 配置 Runner（Ephemeral 模式）
echo "=== Configuring Runner ==="
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
./svc.sh install root

# 启动 Runner 服务
echo "=== Starting Runner service ==="
./svc.sh start

echo "=== User Data Script Completed ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

