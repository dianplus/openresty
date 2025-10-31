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

# 全局变量存储 spot-instance-advisor 的路径
SPOT_INSTANCE_ADVISOR_CMD=""

# 下载并安装 spot-instance-advisor
install_spot_instance_advisor() {
    # 检查是否已安装
    if command -v spot-instance-advisor &> /dev/null; then
        SPOT_INSTANCE_ADVISOR_CMD="spot-instance-advisor"
        log_info "spot-instance-advisor is already installed"
        return 0
    fi

    log_info "Downloading spot-instance-advisor from GitHub maskshell releases..."
    
    # 检测操作系统和架构
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # 标准化架构名称
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    # 标准化操作系统名称
    case "$OS" in
        linux)
            OS="linux"
            ;;
        darwin)
            OS="darwin"
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    log_info "Detected OS: $OS, Architecture: $ARCH"
    
    # GitHub API 获取最新 release
    REPO="maskshell/spot-instance-advisor"
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
    
    log_info "Fetching latest release info from $API_URL"
    
    # 获取最新 release 信息
    RELEASE_INFO=$(curl -sL "$API_URL" || {
        log_error "Failed to fetch release info from GitHub API"
        exit 1
    })
    
    # 解析 release tag
    TAG_NAME=$(echo "$RELEASE_INFO" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    if [ -z "$TAG_NAME" ]; then
        log_error "Failed to parse release tag from GitHub API"
        exit 1
    fi
    
    log_info "Latest release: $TAG_NAME"
    
    # 从 release assets 中查找匹配的二进制文件
    # 可能的命名格式: spot-instance-advisor-<os>-<arch>, spot-instance-advisor-<os>-<arch>.tar.gz, etc.
    ASSETS=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": "[^"]*' | cut -d'"' -f4)
    
    # 尝试匹配可能的文件名模式
    BINARY_NAME=""
    DOWNLOAD_URL=""
    
    # 优先尝试: spot-instance-advisor-<os>-<arch>
    PATTERN="${OS}-${ARCH}"
    for URL in $ASSETS; do
        if echo "$URL" | grep -q "$PATTERN"; then
            BINARY_NAME=$(basename "$URL")
            DOWNLOAD_URL="$URL"
            break
        fi
    done
    
    # 如果没找到，尝试其他可能的模式
    if [ -z "$DOWNLOAD_URL" ]; then
        # 尝试: spot-instance-advisor-<arch>
        PATTERN="${ARCH}"
        for URL in $ASSETS; do
            if echo "$URL" | grep -qi "spot-instance-advisor.*${PATTERN}"; then
                BINARY_NAME=$(basename "$URL")
                DOWNLOAD_URL="$URL"
                break
            fi
        done
    fi
    
    # 如果还是没找到，尝试第一个 asset
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL=$(echo "$ASSETS" | head -1)
        BINARY_NAME=$(basename "$DOWNLOAD_URL")
        log_info "Using first available asset: $BINARY_NAME"
    fi
    
    if [ -z "$DOWNLOAD_URL" ]; then
        log_error "No matching binary found in release assets"
        exit 1
    fi
    
    log_info "Downloading from: $DOWNLOAD_URL"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # 下载文件
    DOWNLOADED_FILE="$TEMP_DIR/$BINARY_NAME"
    if ! curl -sL -o "$DOWNLOADED_FILE" "$DOWNLOAD_URL"; then
        log_error "Failed to download spot-instance-advisor"
        exit 1
    fi
    
    # 如果是压缩包，解压
    if echo "$BINARY_NAME" | grep -qE '\.(tar\.gz|tgz|zip)$'; then
        log_info "Extracting archive..."
        if echo "$BINARY_NAME" | grep -qE '\.(tar\.gz|tgz)$'; then
            tar -xzf "$DOWNLOADED_FILE" -C "$TEMP_DIR"
        elif echo "$BINARY_NAME" | grep -q '\.zip$'; then
            unzip -q "$DOWNLOADED_FILE" -d "$TEMP_DIR"
        fi
        # 查找解压后的二进制文件
        BINARY_FILE=$(find "$TEMP_DIR" -name "spot-instance-advisor" -type f | head -1)
        if [ -z "$BINARY_FILE" ]; then
            # 如果没有找到，尝试查找任何可执行文件
            BINARY_FILE=$(find "$TEMP_DIR" -type f -executable | head -1)
        fi
        if [ -z "$BINARY_FILE" ]; then
            log_error "Failed to find binary in archive"
            exit 1
        fi
        mv "$BINARY_FILE" "$TEMP_DIR/spot-instance-advisor"
    else
        # 直接使用下载的文件
        mv "$DOWNLOADED_FILE" "$TEMP_DIR/spot-instance-advisor"
    fi
    
    # 设置执行权限
    chmod +x "$TEMP_DIR/spot-instance-advisor"
    
    # 移动到 PATH 目录
    # 优先使用 /usr/local/bin（GitHub Actions 通常可写）
    # 否则使用 $HOME/.local/bin
    if [ -w "/usr/local/bin" ] 2>/dev/null; then
        INSTALL_DIR="/usr/local/bin"
        mv "$TEMP_DIR/spot-instance-advisor" "$INSTALL_DIR/spot-instance-advisor"
    else
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"
        mv "$TEMP_DIR/spot-instance-advisor" "$INSTALL_DIR/spot-instance-advisor"
        # 确保 PATH 包含安装目录
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            export PATH="$INSTALL_DIR:$PATH"
        fi
    fi
    
    log_success "spot-instance-advisor installed to $INSTALL_DIR"
    
    # 验证安装并设置命令路径
    # 首先确保 PATH 已更新
    hash -r 2>/dev/null || true
    
    if command -v spot-instance-advisor &> /dev/null; then
        SPOT_INSTANCE_ADVISOR_CMD="spot-instance-advisor"
    elif [ -f "$INSTALL_DIR/spot-instance-advisor" ]; then
        SPOT_INSTANCE_ADVISOR_CMD="$INSTALL_DIR/spot-instance-advisor"
        log_info "Using full path for spot-instance-advisor: $SPOT_INSTANCE_ADVISOR_CMD"
    else
        log_error "spot-instance-advisor binary not found at $INSTALL_DIR"
        exit 1
    fi
    
    log_success "spot-instance-advisor is ready to use"
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

# 确保 spot-instance-advisor 已安装
install_spot_instance_advisor

# 获取阿里云凭证（优先从环境变量，其次从 aliyun CLI 配置）
if [ -n "$ALIYUN_ACCESS_KEY_ID" ] && [ -n "$ALIYUN_ACCESS_KEY_SECRET" ]; then
    ACCESS_KEY_ID="$ALIYUN_ACCESS_KEY_ID"
    ACCESS_KEY_SECRET="$ALIYUN_ACCESS_KEY_SECRET"
    log_info "Using credentials from environment variables"
elif [ -f "$HOME/.aliyun/config.json" ]; then
    # 从 aliyun CLI 配置文件中读取
    log_info "Reading credentials from aliyun CLI config file"
    if command -v jq &> /dev/null; then
        # 使用 jq 解析 JSON（更可靠）
        ACCESS_KEY_ID=$(jq -r '.profiles[0].mode_ak.access_key_id // empty' "$HOME/.aliyun/config.json" 2>/dev/null)
        ACCESS_KEY_SECRET=$(jq -r '.profiles[0].mode_ak.access_key_secret // empty' "$HOME/.aliyun/config.json" 2>/dev/null)
    else
        # 使用 grep 解析（备用方案）
        ACCESS_KEY_ID=$(grep -o '"access_key_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.aliyun/config.json" | head -1 | sed 's/.*"access_key_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        ACCESS_KEY_SECRET=$(grep -o '"access_key_secret"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.aliyun/config.json" | head -1 | sed 's/.*"access_key_secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
else
    log_error "Aliyun credentials not found. Please set ALIYUN_ACCESS_KEY_ID and ALIYUN_ACCESS_KEY_SECRET environment variables or configure aliyun CLI."
    exit 1
fi

if [ -z "$ACCESS_KEY_ID" ] || [ -z "$ACCESS_KEY_SECRET" ]; then
    log_error "Failed to get Aliyun credentials"
    exit 1
fi

# 构建 spot-instance-advisor 命令参数
# 使用正确的参数格式: -key=value 而不是 --key value
ADVISOR_ARGS=(
    "-accessKeyId=$ACCESS_KEY_ID"
    "-accessKeySecret=$ACCESS_KEY_SECRET"
    "-region=$REGION"
    "-mincpu=$MIN_CPU"
    "-maxcpu=$MAX_CPU"
    "-minmem=$MIN_MEMORY"
    "-maxmem=$MAX_MEMORY"
    "-resolution=7"
    "-limit=20"
    "--json"
)

# 如果提供了实例类型（family），添加 -family 参数
if [ -n "$INSTANCE_TYPES" ] && [ "$INSTANCE_TYPES" != "" ]; then
    ADVISOR_ARGS+=("-family=$INSTANCE_TYPES")
fi

log_info "Running spot-instance-advisor with parameters..."
# 查询价格
ALL_PRICES=$($SPOT_INSTANCE_ADVISOR_CMD "${ADVISOR_ARGS[@]}")

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

