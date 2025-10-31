#!/bin/bash
# GitHub Actions Runner Setup Script
# 用于在 ECS 实例上设置和配置 GitHub Actions Runner

set -e  # 遇到错误立即退出

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

# 配置代理设置
setup_proxy() {
    log_info "Setting up proxy configuration..."
    
    if [ -n "$HTTP_PROXY" ]; then
        log_info "Setting HTTP_PROXY: $HTTP_PROXY"
        export HTTP_PROXY="$HTTP_PROXY"
        echo "export HTTP_PROXY=\"$HTTP_PROXY\"" >> /etc/environment
    fi
    
    if [ -n "$HTTPS_PROXY" ]; then
        log_info "Setting HTTPS_PROXY: $HTTPS_PROXY"
        export HTTPS_PROXY="$HTTPS_PROXY"
        echo "export HTTPS_PROXY=\"$HTTPS_PROXY\"" >> /etc/environment
    fi
    
    # 设置 NO_PROXY 默认值
    if [ -n "$NO_PROXY" ]; then
        log_info "Setting NO_PROXY: $NO_PROXY"
        export NO_PROXY="$NO_PROXY"
        echo "export NO_PROXY=\"$NO_PROXY\"" >> /etc/environment
    else
        NO_PROXY_DEFAULT="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,mirrors.tuna.tsinghua.edu.cn,mirrors.aliyun.com,.aliyun.com,.aliyuncs.com,.alicdn.com,.dianplus.cn,.dianjia.io,.taobao.com"
        log_info "Setting NO_PROXY default: $NO_PROXY_DEFAULT"
        export NO_PROXY="$NO_PROXY_DEFAULT"
        echo "export NO_PROXY=\"$NO_PROXY_DEFAULT\"" >> /etc/environment
    fi
    
    log_success "Proxy configuration completed"
}

# 更新系统并安装必要软件
install_dependencies() {
    log_info "Updating system and installing dependencies..."
    
    # 更新系统
    yum update -y
    
    # 安装必要软件
    yum install -y docker git curl wget jq
    
    # 启动 Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Dependencies installed successfully"
}

# 获取最新版本号
get_runner_version() {
    log_info "Getting latest GitHub Actions Runner version..."
    
    # 设置默认版本
    RUNNER_VERSION="2.329.0"
    
    # 尝试从 GitHub API 获取最新版本
    log_info "Fetching latest version from GitHub API..."
    if curl -s --proxy "$HTTP_PROXY" https://api.github.com/repos/actions/runner/releases/latest > api_response.json; then
        log_info "API response saved to api_response.json"
        
        # 检查 jq 是否可用
        if ! which jq >/dev/null 2>&1; then
            log_warning "jq not found, installing..."
            yum install -y jq
        fi
        
        # 解析版本号
        TAG_NAME=$(jq -r .tag_name api_response.json)
        log_info "TAG_NAME: $TAG_NAME"
        
        if [ "$TAG_NAME" != "null" ] && [ -n "$TAG_NAME" ]; then
            RUNNER_VERSION=$(echo "$TAG_NAME" | sed 's/^v//')
            log_success "Got latest version: $RUNNER_VERSION"
        else
            log_warning "Failed to get version from API, using default: $RUNNER_VERSION"
        fi
    else
        log_warning "Failed to fetch from API, using default version: $RUNNER_VERSION"
    fi
    
    # 验证版本号
    if [ -z "$RUNNER_VERSION" ] || [ "$RUNNER_VERSION" = "null" ]; then
        log_error "Failed to get runner version from GitHub API"
        log_info "API Response content:"
        cat api_response.json
        log_info "Using fallback version: 2.329.0"
        RUNNER_VERSION="2.329.0"
    fi
    
    # 清理版本字符串
    if [ -n "$RUNNER_VERSION" ]; then
        RUNNER_VERSION=$(echo "$RUNNER_VERSION" | tr -d '[:space:]')
        log_info "Cleaned version: $RUNNER_VERSION"
    else
        log_error "RUNNER_VERSION is empty, cannot clean"
        exit 1
    fi
    
    echo "$RUNNER_VERSION"
}

# 下载 GitHub Actions Runner
download_runner() {
    local version=$1
    local arch=$2
    
    log_info "Downloading GitHub Actions Runner $version ($arch)..."
    
    # 构建文件名和 URL
    local file="actions-runner-linux-$arch-$version.tar.gz"
    local url="https://github.com/actions/runner/releases/download/v$version/$file"
    
    log_info "URL: $url"
    log_info "FILE: $file"
    
    # 下载文件
    if ! curl -fL --proxy "$HTTP_PROXY" -o "$file" "$url"; then
        log_error "Failed to download runner from $url"
        exit 1
    fi
    
    # 验证下载
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        log_error "Downloaded file is missing or empty"
        exit 1
    fi
    
    # 显示文件大小
    local file_size=$(du -h "$file" | cut -f1)
    log_success "Successfully downloaded $file ($file_size)"
    
    # 提取文件
    log_info "Extracting runner files..."
    if ! tar xzf "$file"; then
        log_error "Failed to extract runner archive"
        exit 1
    fi
    
    # 验证必要文件
    if [ ! -f "config.sh" ] || [ ! -f "run.sh" ]; then
        log_error "Essential runner files missing after extraction"
        exit 1
    fi
    
    log_success "Runner files extracted successfully"
}

# 配置 GitHub Actions Runner
configure_runner() {
    local github_url=$1
    local github_token=$2
    local runner_name=$3
    local runner_labels=$4
    
    log_info "Configuring GitHub Actions Runner..."
    log_info "GitHub URL: $github_url"
    log_info "Runner Name: $runner_name"
    log_info "Runner Labels: $runner_labels"
    log_info "HTTP_PROXY: $HTTP_PROXY"
    log_info "HTTPS_PROXY: $HTTPS_PROXY"
    log_info "NO_PROXY: $NO_PROXY"
    
    # 配置 runner
    if ! ./config.sh --url "$github_url" --token "$github_token" --name "$runner_name" --labels "$runner_labels" --unattended --replace; then
        log_error "Failed to configure runner"
        exit 1
    fi
    
    log_success "Runner configured successfully"
}

# 启动 GitHub Actions Runner
start_runner() {
    log_info "Starting GitHub Actions Runner..."
    
    # 创建日志目录
    mkdir -p /var/log/github-runner
    
    # 启动 runner，同时输出到文件和控制台
    nohup ./run.sh > /var/log/github-runner/runner.log 2>&1 &
    local runner_pid=$!
    echo "$runner_pid" > /var/log/github-runner/runner.pid
    log_info "Runner started with PID: $runner_pid"
    log_info "Runner logs: /var/log/github-runner/runner.log"
    log_info "Runner PID file: /var/log/github-runner/runner.pid"
    
    # 等待并检查状态
    sleep 5
    if ! kill -0 "$runner_pid" 2>/dev/null; then
        log_error "Runner process died immediately"
        log_info "Runner log:"
        cat /var/log/github-runner/runner.log || true
        exit 1
    fi
    
    log_success "Runner is running successfully"
    log_info "To view runner logs: tail -f /var/log/github-runner/runner.log"
}

# 主函数
main() {
    # 创建日志目录
    mkdir -p /var/log/github-runner
    
    # 日志文件路径
    LOG_FILE="/var/log/github-runner/setup.log"
    
    log_info "=== Starting GitHub Actions Runner Setup ==="
    log_info "Timestamp: $(date)"
    log_info "Setup log: $LOG_FILE"
    log_info "All output will be logged to: $LOG_FILE"
    
    # 设置代理
    setup_proxy 2>&1 | tee -a "$LOG_FILE"
    
    # 安装依赖
    install_dependencies 2>&1 | tee -a "$LOG_FILE"
    
    # 切换到工作目录
    cd /root
    
    # 获取版本号
    local runner_version=$(get_runner_version 2>&1 | tee -a "$LOG_FILE" | tail -1)
    log_info "Using runner version: $runner_version"
    
    # 确定架构
    local arch="x64"  # 默认架构，可以通过参数传入
    if [ -n "$1" ]; then
        arch="$1"
    fi
    
    log_info "Using architecture: $arch"
    
    # 下载 runner
    download_runner "$runner_version" "$arch" 2>&1 | tee -a "$LOG_FILE"
    
    # 配置 runner
    local runner_labels="self-hosted,linux"
    if [ "$arch" = "arm64" ]; then
        runner_labels="$runner_labels,ARM64"
    else
        runner_labels="$runner_labels,AMD64"
    fi
    
    configure_runner \
        "https://github.com/dianplus/openresty" \
        "$GITHUB_TOKEN" \
        "$RUNNER_NAME" \
        "$runner_labels" 2>&1 | tee -a "$LOG_FILE"
    
    # 启动 runner
    start_runner 2>&1 | tee -a "$LOG_FILE"
    
    log_success "=== GitHub Actions Runner Setup Completed ==="
    log_info "Timestamp: $(date)"
    log_info "Logs location:"
    log_info "  - Setup log: /var/log/github-runner/setup.log"
    log_info "  - Runner log: /var/log/github-runner/runner.log"
    log_info "  - User data log: /var/log/user-data.log"
}

# 执行主函数
main "$@"
