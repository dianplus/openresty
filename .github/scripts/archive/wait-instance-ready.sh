#!/bin/bash
# Wait for ECS instance to be ready (Running status)
# Usage: ./wait-instance-ready.sh <instance-id> [max-wait-seconds]
# Default max wait: 600 seconds (10 minutes)

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

log_warning() {
    echo "⚠️  $1"
}

# 参数检查
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <instance-id> [max-wait-seconds]"
    exit 1
fi

INSTANCE_ID=$1
MAX_WAIT=${2:-600}  # 默认最多等待 10 分钟
SLEEP_INTERVAL=10   # 每次检查间隔 10 秒
ELAPSED=0

log_info "Waiting for instance $INSTANCE_ID to be ready..."
log_info "Maximum wait time: ${MAX_WAIT}s"

# 轮询检查实例状态
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(aliyun ecs DescribeInstances --InstanceIds "[\"$INSTANCE_ID\"]" --Output json | jq -r '.Instances.Instance[0].Status')
    
    log_info "Instance status: $STATUS (elapsed: ${ELAPSED}s)"
    
    if [ "$STATUS" = "Running" ]; then
        log_success "Instance is running"
        exit 0
    elif [ "$STATUS" = "Stopped" ] || [ "$STATUS" = "Stopping" ]; then
        log_error "Instance failed to start (status: $STATUS)"
        exit 1
    fi
    
    sleep $SLEEP_INTERVAL
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
done

log_error "Timeout waiting for instance to be ready (waited ${MAX_WAIT}s)"
exit 1

