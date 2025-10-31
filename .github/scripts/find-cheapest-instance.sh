#!/bin/bash
# Find the cheapest spot instance in a given region
# Usage: ./find-cheapest-instance.sh <region> <instance-types> <min-cpu> <max-cpu> <min-memory> <max-memory>
# Outputs: cheapest_instance, cheapest_zone, spot_price_limit (via GitHub Actions outputs)

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
if [ $# -lt 6 ]; then
    log_error "Usage: $0 <region> <instance-types> <min-cpu> <max-cpu> <min-memory> <max-memory>"
    exit 1
fi

REGION=$1
INSTANCE_TYPES=$2
MIN_CPU=$3
MAX_CPU=$4
MIN_MEMORY=$5
MAX_MEMORY=$6

log_info "Querying spot instance prices in region: $REGION"
log_info "Instance types: $INSTANCE_TYPES"
log_info "CPU range: $MIN_CPU - $MAX_CPU"
log_info "Memory range: $MIN_MEMORY - $MAX_MEMORY"

# 查询价格
ALL_PRICES=$(spot-instance-advisor \
    --region "$REGION" \
    --instance-types "$INSTANCE_TYPES" \
    --min-cpu "$MIN_CPU" \
    --max-cpu "$MAX_CPU" \
    --min-memory "$MIN_MEMORY" \
    --max-memory "$MAX_MEMORY" \
    --output json)

# 查找最便宜的实例
CHEAPEST=$(echo "$ALL_PRICES" | jq -r '.spot_prices[] | select(.instance_type | startswith("ecs.c8y")) | select(.price_per_core != null) | [.instance_type, .zone, .price_per_core] | @csv' | sort -t',' -k3 -n | head -1)

if [ -z "$CHEAPEST" ]; then
    log_error "No suitable instance found"
    exit 1
fi

CHEAPEST_INSTANCE=$(echo "$CHEAPEST" | cut -d',' -f1 | tr -d '"')
CHEAPEST_ZONE=$(echo "$CHEAPEST" | cut -d',' -f2 | tr -d '"')
PRICE_PER_CORE=$(echo "$CHEAPEST" | cut -d',' -f3 | tr -d '"')

log_info "Cheapest instance: $CHEAPEST_INSTANCE"
log_info "Cheapest zone: $CHEAPEST_ZONE"
log_info "Price per core: $PRICE_PER_CORE"

# 从实例类型名称提取 CPU 核心数
if [[ "$CHEAPEST_INSTANCE" =~ \.8xlarge$ ]]; then
    CPU_CORES=32
elif [[ "$CHEAPEST_INSTANCE" =~ \.4xlarge$ ]]; then
    CPU_CORES=16
elif [[ "$CHEAPEST_INSTANCE" =~ \.2xlarge$ ]]; then
    CPU_CORES=8
elif [[ "$CHEAPEST_INSTANCE" =~ \.xlarge$ ]]; then
    CPU_CORES=4
elif [[ "$CHEAPEST_INSTANCE" =~ \.large$ ]]; then
    CPU_CORES=2
else
    CPU_CORES=8
fi

# 计算总价格: 每核心价格 × CPU核心数 × 1.2 (20% 缓冲)
SPOT_PRICE_LIMIT=$(echo "$PRICE_PER_CORE * $CPU_CORES * 1.2" | bc -l)

log_info "CPU cores: $CPU_CORES"
log_info "Spot price limit: $SPOT_PRICE_LIMIT"

# 输出到 GitHub Actions
echo "cheapest_instance=$CHEAPEST_INSTANCE" >> $GITHUB_OUTPUT
echo "cheapest_zone=$CHEAPEST_ZONE" >> $GITHUB_OUTPUT
echo "spot_price_limit=$SPOT_PRICE_LIMIT" >> $GITHUB_OUTPUT

log_success "Found cheapest instance configuration"

