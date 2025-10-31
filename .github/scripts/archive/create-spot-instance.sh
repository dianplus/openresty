#!/bin/bash
# Create a spot ECS instance with GitHub Actions Runner
# Usage: ./create-spot-instance.sh <instance-type> <zone> <spot-price-limit> <image-id> <security-group-id> <vswitch-id> <key-pair-name> <github-token> <runner-name> <architecture>
# Outputs: instance_id (via GitHub Actions outputs)

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
if [ $# -lt 10 ]; then
    log_error "Usage: $0 <instance-type> <zone> <spot-price-limit> <image-id> <security-group-id> <vswitch-id> <key-pair-name> <github-token> <runner-name> <architecture>"
    exit 1
fi

INSTANCE_TYPE=$1
ZONE=$2
SPOT_PRICE_LIMIT=$3
IMAGE_ID=$4
SECURITY_GROUP_ID=$5
VSWITCH_ID=$6
KEY_PAIR_NAME=$7
GITHUB_TOKEN=$8
RUNNER_NAME=$9
ARCHITECTURE=${10}

log_info "Creating spot instance..."
log_info "Instance type: $INSTANCE_TYPE"
log_info "Zone: $ZONE"
log_info "Spot price limit: $SPOT_PRICE_LIMIT"
log_info "Architecture: $ARCHITECTURE"

# 创建 user_data.sh 脚本
log_info "Generating user data script..."
# 使用双引号 heredoc 允许变量替换，但需要对 $ 进行转义以避免过早展开
cat > user_data.sh << USERDATA_EOF
#!/bin/bash
set -e

# Export environment variables needed by setup-runner.sh
export GITHUB_TOKEN="$GITHUB_TOKEN"
export RUNNER_NAME="$RUNNER_NAME-\$(date +%s)"

# Set proxy variables if available (from ECS instance metadata or defaults)
# These will be properly configured by setup-runner.sh if needed
[ -n "\${HTTP_PROXY:-}" ] && export HTTP_PROXY="\${HTTP_PROXY}"
[ -n "\${HTTPS_PROXY:-}" ] && export HTTPS_PROXY="\${HTTPS_PROXY}"
[ -n "\${NO_PROXY:-}" ] && export NO_PROXY="\${NO_PROXY}"

# Download and execute the setup script
# Use HTTP_PROXY if set, otherwise proceed without proxy
if [ -n "\${HTTP_PROXY:-}" ]; then
  curl -s --proxy "\${HTTP_PROXY}" https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/setup-runner.sh -o setup-runner.sh
else
  curl -s https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/setup-runner.sh -o setup-runner.sh
fi

chmod +x setup-runner.sh

# Execute the setup script
./setup-runner.sh $ARCHITECTURE
USERDATA_EOF

# 创建实例
log_info "Creating ECS instance..."
INSTANCE_ID=$(aliyun ecs RunInstances \
    --ImageId "$IMAGE_ID" \
    --InstanceType "$INSTANCE_TYPE" \
    --SecurityGroupId "$SECURITY_GROUP_ID" \
    --VSwitchId "$VSWITCH_ID" \
    --ZoneId "$ZONE" \
    --SpotStrategy SpotWithPriceLimit \
    --SpotPriceLimit "$SPOT_PRICE_LIMIT" \
    --SystemDisk.Category cloud_essd \
    --SystemDisk.Size 40 \
    --KeyPairName "$KEY_PAIR_NAME" \
    --UserData "$(base64 -w 0 user_data.sh)" \
    --Output json | jq -r '.InstanceIdSets.InstanceIdSet[0]')

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
    log_error "Failed to create instance"
    exit 1
fi

# 输出到 GitHub Actions
echo "instance_id=$INSTANCE_ID" >> $GITHUB_OUTPUT

log_success "Created instance: $INSTANCE_ID"

