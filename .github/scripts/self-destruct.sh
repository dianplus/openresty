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

# 配置 Aliyun CLI
# 使用实例角色进行认证（实例角色会自动通过元数据服务获取，无需配置）
log "Using instance role for authentication"
# 如果实例配置了 RamRoleName，Aliyun CLI 会自动使用实例角色

# 检查 Aliyun CLI 是否已安装
if ! command -v aliyun &> /dev/null; then
    log "Error: Aliyun CLI is not installed"
    exit 1
fi

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

