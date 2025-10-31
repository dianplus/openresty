#!/bin/bash
# Configure Aliyun CLI for GitHub Actions
# Usage: ./configure-aliyun-cli.sh <region> <access-key-id> <access-key-secret>

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
if [ $# -lt 3 ]; then
    log_error "Usage: $0 <region> <access-key-id> <access-key-secret>"
    exit 1
fi

REGION=$1
ACCESS_KEY_ID=$2
ACCESS_KEY_SECRET=$3

log_info "Configuring Aliyun CLI..."

# 下载并安装 Aliyun CLI
if ! command -v aliyun &> /dev/null; then
    log_info "Downloading Aliyun CLI..."
    wget -q https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
    tar xzf aliyun-cli-linux-latest-amd64.tgz
    sudo mv aliyun /usr/local/bin/
    rm -f aliyun-cli-linux-latest-amd64.tgz
    log_success "Aliyun CLI installed"
else
    log_info "Aliyun CLI already installed"
fi

# 配置 Aliyun CLI
log_info "Configuring Aliyun CLI with region: $REGION"
aliyun configure set \
    --profile default \
    --mode AK \
    --region "$REGION" \
    --access-key-id "$ACCESS_KEY_ID" \
    --access-key-secret "$ACCESS_KEY_SECRET"

log_success "Aliyun CLI configured successfully"

