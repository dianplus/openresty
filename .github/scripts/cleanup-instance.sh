#!/bin/bash
# Cleanup (delete) an ECS instance
# Usage: ./cleanup-instance.sh <instance-id> [force]

set -e

# 颜色输出函数
log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

# 参数检查
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <instance-id> [force]"
    exit 1
fi

INSTANCE_ID=$1
FORCE=${2:-true}  # 默认强制删除

log_info "Cleaning up instance: $INSTANCE_ID"
log_info "Force delete: $FORCE"

# 删除实例
if aliyun ecs DeleteInstance --InstanceId "$INSTANCE_ID" --Force "$FORCE"; then
    log_success "Instance cleaned up successfully"
else
    log_error "Failed to cleanup instance"
    exit 1
fi

