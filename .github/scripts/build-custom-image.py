#!/usr/bin/env python3
"""
构建自定义镜像脚本
基于阿里云 Ubuntu 24 镜像构建预装工具的自定义镜像
"""

import base64
import json
import os
import re
import subprocess
import sys
import time
from typing import Optional, Tuple


def error_exit(message: str) -> None:
    """输出错误信息并退出"""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def get_env_var(name: str, default: Optional[str] = None) -> str:
    """获取环境变量"""
    value = os.environ.get(name, default)
    if value is None:
        error_exit(f"{name} is required")
    return value


def create_user_data_script(arch: str) -> str:
    """创建 User Data 脚本，用于安装预装工具"""
    # 检测架构
    if arch.lower() == "amd64":
        runner_arch = "x64"
        advisor_arch = "amd64"
    elif arch.lower() == "arm64":
        runner_arch = "arm64"
        advisor_arch = "arm64"
    else:
        error_exit(f"Unsupported architecture: {arch}")

    # 获取工具版本（从环境变量或使用最新）
    runner_version = os.environ.get("RUNNER_VERSION", "2.311.0")
    advisor_version = os.environ.get("ADVISOR_VERSION", "")

    script = f"""#!/bin/bash
set -euo pipefail

# 记录日志
exec > >(tee /var/log/image-build.log)
exec 2>&1

echo "=== Image Build Script Started ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Architecture: {arch}"

# 更新系统
echo "=== Updating system ==="
apt-get update -y
apt-get install -y curl wget git jq

# 安装 Aliyun CLI
echo "=== Installing Aliyun CLI ==="
ALIYUN_CLI_VERSION=$(curl -s https://api.github.com/repos/aliyun/aliyun-cli/releases/latest | jq -r '.tag_name' | sed 's/^v//' || echo "3.0.0")
echo "Using Aliyun CLI version: $ALIYUN_CLI_VERSION"
curl -sSL https://aliyuncli.alicdn.com/aliyun-cli-linux-{advisor_arch}-${{ALIYUN_CLI_VERSION}}.tgz | tar -xz -C /tmp
mv /tmp/aliyun /usr/local/bin/aliyun
chmod +x /usr/local/bin/aliyun
aliyun --version

# 安装 spot-instance-advisor
echo "=== Installing spot-instance-advisor ==="
"""
    
    if advisor_version:
        script += f'ADVISOR_VERSION="{advisor_version}"\n'
    else:
        script += 'ADVISOR_VERSION=$(curl -s https://api.github.com/repos/maskshell/spot-instance-advisor/releases/latest | jq -r \'.tag_name\' || echo "v1.0.1")\n'
    
    script += f"""echo "Using spot-instance-advisor version: $ADVISOR_VERSION"
ADVISOR_URL="https://github.com/maskshell/spot-instance-advisor/releases/download/${{ADVISOR_VERSION}}/spot-instance-advisor-linux-{advisor_arch}"
curl -L -f -o /usr/local/bin/spot-instance-advisor "${{ADVISOR_URL}}"
chmod +x /usr/local/bin/spot-instance-advisor
spot-instance-advisor --version || echo "Warning: Version check failed"

# 安装 Docker Engine
echo "=== Installing Docker Engine ==="
# 安装必要的依赖
apt-get install -y ca-certificates gnupg lsb-release

# 添加 Docker 官方 GPG 密钥
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置 Docker 仓库
echo \\
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \\
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新 apt 包索引
apt-get update -y

# 安装 Docker Engine、CLI 和 Containerd
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动 Docker daemon 并设置为开机自启
systemctl start docker
systemctl enable docker

# 验证 Docker 安装
docker --version
docker info

# 配置 Docker Buildx（Docker 20.10+ 自带，但需要创建 builder 实例）
echo "=== Configuring Docker Buildx ==="
docker buildx version || echo "Warning: Buildx version check failed"
# 创建默认 builder 实例（如果不存在）
docker buildx create --name builder --use 2>/dev/null || docker buildx use builder 2>/dev/null || true
docker buildx inspect --bootstrap || echo "Warning: Buildx builder setup failed"

# 验证 Buildx
docker buildx ls

# 安装 GitHub Actions Runner（预装但未配置）
echo "=== Installing GitHub Actions Runner ==="
RUNNER_DIR="/opt/actions-runner"
mkdir -p "${{RUNNER_DIR}}"
RUNNER_VERSION="{runner_version}"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${{RUNNER_VERSION}}/actions-runner-linux-{runner_arch}-${{RUNNER_VERSION}}.tar.gz"
echo "Using Runner version: ${{RUNNER_VERSION}}"
echo "Downloading runner from: ${{RUNNER_URL}}"
curl -o /tmp/runner.tar.gz -L --retry 5 --retry-all-errors --connect-timeout 10 --max-time 300 "${{RUNNER_URL}}"
tar xzf /tmp/runner.tar.gz -C "${{RUNNER_DIR}}"
rm /tmp/runner.tar.gz
echo "Runner installed to ${{RUNNER_DIR}}"

# 生成版本信息文件
echo "=== Generating version info ==="
VERSION_FILE="/opt/image-version.json"
# 获取 Docker 和 Buildx 版本
DOCKER_VERSION=$(docker --version | sed 's/.*version //' | sed 's/,.*//' || echo "unknown")
BUILDX_VERSION=$(docker buildx version | sed 's/.*v//' || echo "unknown")
cat > "${{VERSION_FILE}}" << 'VERSION_EOF'
{{
  "base_image": "BASE_IMAGE_ID_PLACEHOLDER",
  "base_image_name": "BASE_IMAGE_NAME_PLACEHOLDER",
  "base_image_creation_time": "BASE_IMAGE_CREATION_TIME_PLACEHOLDER",
  "aliyun_cli_version": "${{ALIYUN_CLI_VERSION}}",
  "advisor_version": "${{ADVISOR_VERSION}}",
  "runner_version": "${{RUNNER_VERSION}}",
  "docker_version": "${{DOCKER_VERSION}}",
  "buildx_version": "${{BUILDX_VERSION}}",
  "build_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "architecture": "{arch}"
}}
VERSION_EOF
# 替换占位符
sed -i "s|BASE_IMAGE_ID_PLACEHOLDER|${{BASE_IMAGE_ID}}|g" "${{VERSION_FILE}}"
sed -i "s|BASE_IMAGE_NAME_PLACEHOLDER|${{BASE_IMAGE_NAME}}|g" "${{VERSION_FILE}}"
sed -i "s|BASE_IMAGE_CREATION_TIME_PLACEHOLDER|${{BASE_IMAGE_CREATION_TIME}}|g" "${{VERSION_FILE}}"
cat "${{VERSION_FILE}}"

# 清理临时文件和日志
echo "=== Cleaning up temporary files and logs ==="

# 清理 apt 缓存
apt-get clean -y
apt-get autoclean -y
rm -rf /var/lib/apt/lists/*

# 清理临时文件
rm -rf /tmp/*
rm -rf /var/tmp/*

# 清理下载的临时文件（如果存在）
rm -f /tmp/aliyun-cli-*.tgz
rm -f /tmp/spot-instance-advisor-*
rm -f /tmp/runner.tar.gz

# 清理日志文件（保留版本信息文件）
rm -f /var/log/image-build.log
rm -f /var/log/apt/*.log
rm -f /var/log/dpkg.log

# 清理 bash 历史记录
rm -f /root/.bash_history
rm -f /home/*/.bash_history 2>/dev/null || true

# 清理系统日志（可选，保留重要日志）
journalctl --vacuum-time=1s 2>/dev/null || true
rm -rf /var/log/journal/* 2>/dev/null || true

# 清理其他临时文件
find /var/log -type f -name "*.log" -exec truncate -s 0 {{}} \\; 2>/dev/null || true
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true

# 清理包管理器缓存
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*

# 清理系统临时文件
rm -rf /var/cache/debconf/*-old
rm -rf /var/lib/dpkg/*-old

# 清理 SSH 主机密钥（如果存在，避免所有实例使用相同密钥）
rm -f /etc/ssh/ssh_host_*_key
rm -f /etc/ssh/ssh_host_*_key.pub

# 清理网络配置缓存
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true

# 清理 cloud-init 缓存（如果存在）
rm -rf /var/lib/cloud/instances/*/sem 2>/dev/null || true

# 清理系统缓存
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

echo "Cleanup completed"

# 创建镜像构建完成标志文件（用于自毁脚本检测）
touch /opt/image-build-complete.flag
echo "Image build completed, ready for image creation" > /opt/image-build-complete.flag

echo "=== Image Build Script Completed ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 安装并配置自毁脚本（等待镜像创建完成后自动删除实例）
echo "=== Installing self-destruct mechanism ==="

# 创建自毁脚本
cat > /usr/local/bin/self-destruct.sh << 'SELF_DESTRUCT_EOF'
#!/bin/bash

# 实例自毁脚本
# 在镜像创建完成后自动删除 ECS 实例
# 使用实例角色（RamRoleName）获取权限进行认证

set -euo pipefail

# 日志文件
LOG_FILE="/var/log/self-destruct.log"

# 记录日志函数
log() {{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${{LOG_FILE}}"
}}

log "=== Instance Self-Destruct Script Started ==="

# 等待镜像构建完成标志文件（最多等待 2 小时）
MAX_WAIT=7200  # 2 小时
WAIT_INTERVAL=60  # 每分钟检查一次
ELAPSED=0

log "Waiting for image build to complete..."
while [[ ! -f /opt/image-build-complete.flag ]] && [[ ${{ELAPSED}} -lt ${{MAX_WAIT}} ]]; do
    sleep ${{WAIT_INTERVAL}}
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    log "Still waiting for image build completion... (${{ELAPSED}}s / ${{MAX_WAIT}}s)"
done

if [[ ! -f /opt/image-build-complete.flag ]]; then
    log "Warning: Image build completion flag not found after ${{MAX_WAIT}}s, proceeding with self-destruct anyway"
else
    log "Image build completion flag found, proceeding with self-destruct"
fi

# 额外等待一段时间，确保镜像创建完成（从外部脚本触发镜像创建）
log "Waiting additional 5 minutes for image creation to complete..."
sleep 300

# 获取实例 ID（通过阿里云元数据服务）
METADATA_URL="http://100.100.100.200/latest/meta-data"
INSTANCE_ID=$(curl -s --connect-timeout 5 --max-time 10 "${{METADATA_URL}}/instance-id" || echo "")
REGION_ID=$(curl -s --connect-timeout 5 --max-time 10 "${{METADATA_URL}}/region-id" || echo "")

if [[ -z "${{INSTANCE_ID}}" ]]; then
    log "Error: Failed to get instance ID from metadata service"
    exit 1
fi

if [[ -z "${{REGION_ID}}" ]]; then
    log "Error: Failed to get region ID from metadata service"
    exit 1
fi

log "Instance ID: ${{INSTANCE_ID}}"
log "Region ID: ${{REGION_ID}}"

# 检查 Aliyun CLI 是否已安装
if ! command -v aliyun &> /dev/null; then
    log "Error: Aliyun CLI is not installed"
    exit 1
fi

# 配置 Aliyun CLI 使用实例角色认证
# 获取实例角色名称（从元数据服务）
RAM_ROLE_NAME=$(curl -s --connect-timeout 5 --max-time 10 "${{METADATA_URL}}/ram/security-credentials/" || echo "")

if [[ -z "${{RAM_ROLE_NAME}}" ]]; then
    log "Error: Failed to get RAM role name from metadata service"
    log "Please ensure the instance has a RAM role attached"
    exit 1
fi

log "RAM Role Name: ${{RAM_ROLE_NAME}}"
log "Configuring Aliyun CLI to use instance role authentication"

# 配置 aliyun cli 使用实例角色认证
# 使用非交互式方式配置
aliyun configure set \
    --mode EcsRamRole \
    --ram-role-name "${{RAM_ROLE_NAME}}" \
    --region "${{REGION_ID}}" 2>&1 | tee -a "${{LOG_FILE}}" || {{
    log "Error: Failed to configure Aliyun CLI"
    exit 1
}}

log "Aliyun CLI configured successfully"

# 等待一段时间，确保镜像创建完成
log "Waiting 10 seconds before self-destruct..."
sleep 10

# 删除实例
log "Deleting instance: ${{INSTANCE_ID}}"
RESPONSE=$(aliyun ecs DeleteInstance \
    --RegionId "${{REGION_ID}}" \
    --InstanceId "${{INSTANCE_ID}}" \
    --Force true 2>&1)

EXIT_CODE=$?

if [[ ${{EXIT_CODE}} -ne 0 ]]; then
    log "Error: Failed to delete instance (exit code: ${{EXIT_CODE}})"
    log "Response: ${{RESPONSE}}"
    exit ${{EXIT_CODE}}
fi

log "Instance deleted successfully: ${{INSTANCE_ID}}"
log "=== Instance Self-Destruct Script Completed ==="
SELF_DESTRUCT_EOF

chmod +x /usr/local/bin/self-destruct.sh

# 创建 systemd service，在镜像构建完成后执行自毁脚本
echo "=== Creating self-destruct systemd service ==="
cat > /etc/systemd/system/self-destruct.service << 'SERVICE_EOF'
[Unit]
Description=Instance Self-Destruct Service (Image Builder)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# 等待镜像构建完成标志文件后执行自毁脚本
ExecStart=/bin/bash -c 'while [[ ! -f /opt/image-build-complete.flag ]]; do sleep 60; done; sleep 300; /usr/local/bin/self-destruct.sh'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable self-destruct.service
systemctl start self-destruct.service

echo "Self-destruct service created, enabled and started"
echo "Instance will be automatically deleted after image creation completes"
"""

    return script


def get_image_from_family(region_id: str, image_family: str) -> Optional[dict]:
    """通过镜像族系获取最新的镜像信息"""
    cmd = [
        "aliyun",
        "ecs",
        "DescribeImageFromFamily",
        "--RegionId",
        region_id,
        "--ImageFamily",
        image_family,
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=False, timeout=30
        )

        if result.returncode != 0:
            print(f"Warning: Failed to query image from family {image_family} (exit code: {result.returncode})", file=sys.stderr)
            if result.stderr:
                print(f"Error output: {result.stderr[:200]}", file=sys.stderr)
            return None

        if result.stdout:
            try:
                data = json.loads(result.stdout)
                
                # DescribeImageFromFamily 返回的镜像信息在 Image 字段中
                if "Image" in data and data["Image"]:
                    image = data["Image"]
                    image_id = image.get("ImageId", "")
                    image_name = image.get("ImageName", "")
                    creation_time = image.get("CreationTime", "")
                    size_gb = image.get("Size", 0)  # DescribeImageFromFamily 返回的 Size 字段单位是 GB
                    
                    if image_id:
                        print(f"Found latest image from family {image_family}: {image_id} ({image_name})", file=sys.stderr)
                        result = {
                            "ImageId": image_id,
                            "ImageName": image_name,
                            "CreationTime": creation_time,
                        }
                        # 如果包含 Size 字段，直接以 GB 为单位添加到返回结果中
                        if size_gb:
                            result["Size"] = size_gb
                            print(f"Image size from family: {size_gb}GB", file=sys.stderr)
                        return result
                    else:
                        print(f"Warning: Image from family {image_family} has no ImageId", file=sys.stderr)
                else:
                    print(f"Warning: No image found in response for family {image_family}", file=sys.stderr)
            except json.JSONDecodeError as e:
                print(f"Warning: Failed to parse JSON response: {e}", file=sys.stderr)
                if result.stderr:
                    print(f"Error output: {result.stderr[:200]}", file=sys.stderr)
                return None

        return None
    except subprocess.TimeoutExpired:
        print(f"Warning: Query image from family {image_family} timeout", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Warning: Failed to query image from family {image_family}: {e}", file=sys.stderr)
        return None


def get_image_info_by_id(region_id: str, image_id: str) -> Optional[dict]:
    """通过镜像 ID 获取镜像详细信息"""
    # 尝试两种参数格式：直接字符串，或者 JSON 数组
    for image_id_param in [image_id, json.dumps([image_id])]:
        cmd = [
            "aliyun",
            "ecs",
            "DescribeImages",
            "--RegionId",
            region_id,
            "--ImageId",
            image_id_param,
        ]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=False, timeout=30
            )

            if result.returncode != 0:
                continue

            if result.stdout:
                try:
                    data = json.loads(result.stdout)

                    if (
                        "Images" in data
                        and "Image" in data["Images"]
                        and len(data["Images"]["Image"]) > 0
                    ):
                        image = data["Images"]["Image"][0]
                        image_id_found = image.get("ImageId", "")
                        image_name = image.get("ImageName", "")
                        creation_time = image.get("CreationTime", "")
                        # DescribeImages API 返回的 Size 字段单位是 GB（与 DescribeImageFromFamily 一致）
                        size_gb = image.get("Size", 0)
                        
                        if image_id_found == image_id:
                            result = {
                                "ImageId": image_id,
                                "ImageName": image_name,
                                "CreationTime": creation_time,
                            }
                            # 如果包含 Size 字段，直接以 GB 为单位添加到返回结果中
                            if size_gb:
                                result["Size"] = int(size_gb)  # 确保是整数
                            return result
                except json.JSONDecodeError:
                    continue

        except subprocess.TimeoutExpired:
            continue
        except Exception:
            continue

    return None


def get_base_image_info(region_id: str, arch: str) -> dict:
    """
    获取基础镜像信息的统一函数
    
    支持多种方式（按优先级）：
    1. 从镜像族系获取（ALIYUN_IMAGE_FAMILY）
    2. 从环境变量直接获取镜像 ID（BASE_IMAGE_ID，向后兼容）
    
    返回包含 ImageId, ImageName, CreationTime 的字典
    """
    # 方式1：优先从镜像族系获取
    image_family = os.environ.get("ALIYUN_IMAGE_FAMILY")
    
    if image_family:
        print(f"Getting latest image from family: {image_family}", file=sys.stderr)
        image_info = get_image_from_family(region_id, image_family)
        
        if image_info:
            return image_info
        else:
            print(f"Warning: Failed to get image from family {image_family}, falling back to BASE_IMAGE_ID", file=sys.stderr)
    
    # 方式2：从环境变量直接获取镜像 ID（向后兼容）
    image_id = os.environ.get("BASE_IMAGE_ID")
    image_name = os.environ.get("BASE_IMAGE_NAME", "")
    image_creation_time = os.environ.get("BASE_IMAGE_CREATION_TIME", "")
    
    if not image_id:
        error_exit(
            "Either ALIYUN_IMAGE_FAMILY or BASE_IMAGE_ID must be set. "
            "If using BASE_IMAGE_ID, it must be provided."
        )
    
    # 如果只有镜像 ID，尝试查询镜像的详细信息
    image_size_gb = None
    if not image_name or not image_creation_time:
        print(f"Querying image details for {image_id}...", file=sys.stderr)
        image_info = get_image_info_by_id(region_id, image_id)
        if image_info:
            image_name = image_info.get("ImageName", image_name)
            image_creation_time = image_info.get("CreationTime", image_creation_time)
            image_size_gb = image_info.get("Size")  # 已经转换为 GB
            print(f"Found image details: {image_id} ({image_name}, created: {image_creation_time})", file=sys.stderr)
            if image_size_gb:
                print(f"Image size from query: {image_size_gb}GB", file=sys.stderr)
        else:
            print(f"Warning: Failed to query image details for {image_id}, using provided values", file=sys.stderr)
    
    result = {
        "ImageId": image_id,
        "ImageName": image_name,
        "CreationTime": image_creation_time,
    }
    # 如果获取到了 Size（单位：GB），添加到返回结果中
    if image_size_gb:
        result["Size"] = image_size_gb
    return result


def get_image_size(region_id: str, image_id: str) -> Optional[int]:
    """查询镜像大小（单位：GB）"""
    # 尝试两种参数格式：直接字符串，或者 JSON 数组（虽然参数名是单数，但可能支持数组格式）
    for image_id_param in [image_id, json.dumps([image_id])]:
        cmd = [
            "aliyun",
            "ecs",
            "DescribeImages",
            "--RegionId",
            region_id,
            "--ImageId",
            image_id_param,
        ]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=False, timeout=30
            )

            # 即使返回码非零，也尝试解析输出
            if result.stdout:
                try:
                    data = json.loads(result.stdout)

                    if (
                        "Images" in data
                        and "Image" in data["Images"]
                        and len(data["Images"]["Image"]) > 0
                    ):
                        image = data["Images"]["Image"][0]
                        # DescribeImages API 返回的 Size 字段单位是 GB（与 DescribeImageFromFamily 一致）
                        size_gb = image.get("Size", 0)
                        if size_gb:
                            print(f"Successfully queried image size: {size_gb}GB", file=sys.stderr)
                            return int(size_gb)  # 确保返回整数
                        else:
                            print(f"Warning: Image {image_id} has no Size field", file=sys.stderr)
                    else:
                        print(f"Warning: No image found in response for {image_id}", file=sys.stderr)
                except json.JSONDecodeError as e:
                    # JSON 解析失败，继续尝试下一种格式
                    print(f"Warning: Failed to parse JSON response: {e}", file=sys.stderr)
                    if result.stderr:
                        print(f"Error output: {result.stderr[:200]}", file=sys.stderr)
                    continue

            # 如果返回码非零，输出错误信息
            if result.returncode != 0:
                print(f"Warning: Command failed with exit code {result.returncode}", file=sys.stderr)
                if result.stderr:
                    print(f"Error output: {result.stderr[:200]}", file=sys.stderr)
                continue

        except subprocess.TimeoutExpired:
            print("Warning: Query image size timeout", file=sys.stderr)
            continue
        except Exception as e:
            print(f"Warning: Failed to query image size: {e}", file=sys.stderr)
            continue

    print(f"Warning: Failed to query image size for {image_id} after trying all formats", file=sys.stderr)
    return None


def get_supported_disk_category(
    region_id: str, instance_type: str, zone_id: Optional[str] = None
) -> str:
    """获取实例类型支持的系统盘类型（降级策略）"""
    # 磁盘类型优先级：cloud_essd -> cloud_ssd -> cloud_efficiency
    disk_categories = ["cloud_essd", "cloud_ssd", "cloud_efficiency"]

    # 如果没有指定可用区，尝试查询（可选）
    if not zone_id:
        # 先尝试查询实例类型支持的磁盘类型
        try:
            cmd = [
                "aliyun",
                "ecs",
                "DescribeAvailableResource",
                "--RegionId",
                region_id,
                "--InstanceType",
                instance_type,
                "--DestinationResource",
                "SystemDisk",
            ]
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=True, timeout=30
            )
            data = json.loads(result.stdout)

            # 解析支持的磁盘类型
            if (
                "AvailableZones" in data
                and "AvailableZone" in data["AvailableZones"]
                and len(data["AvailableZones"]["AvailableZone"]) > 0
            ):
                zone = data["AvailableZones"]["AvailableZone"][0]
                if (
                    "AvailableResources" in zone
                    and "AvailableResource" in zone["AvailableResources"]
                    and len(zone["AvailableResources"]["AvailableResource"]) > 0
                ):
                    resource = zone["AvailableResources"]["AvailableResource"][0]
                    if (
                        "SupportedResources" in resource
                        and "SupportedResource" in resource["SupportedResources"]
                    ):
                        supported = resource["SupportedResources"]["SupportedResource"]
                        supported_categories = [
                            r.get("Value", "") for r in supported if r.get("Value", "")
                        ]

                        # 按优先级选择第一个支持的磁盘类型
                        for category in disk_categories:
                            if category in supported_categories:
                                print(
                                    f"Instance type {instance_type} supports disk category: {category}",
                                    file=sys.stderr,
                                )
                                return category

        except (subprocess.SubprocessError, json.JSONDecodeError, KeyError) as e:
            print(
                f"Warning: Failed to query supported disk categories: {e}",
                file=sys.stderr,
            )

    # 如果查询失败，使用降级策略：尝试创建实例，如果失败则降级
    # 这里先返回 cloud_essd，如果创建失败，调用方可以重试其他类型
    return "cloud_essd"


def create_instance(
    region_id: str,
    image_id: str,
    instance_type: str,
    security_group_id: str,
    vswitch_id: str,
    instance_name: str,
    user_data_b64: str,
    key_pair_name: Optional[str] = None,
    ram_role_name: Optional[str] = None,
    spot_strategy: str = "SpotAsPriceGo",
    spot_price_limit: Optional[str] = None,
    system_disk_category: Optional[str] = None,
    tags: Optional[dict] = None,
    image_size_gb: Optional[int] = None,
) -> Tuple[int, str]:
    """创建 ECS Spot 实例"""
    # 如果没有指定磁盘类型，自动检测
    if not system_disk_category:
        system_disk_category = get_supported_disk_category(region_id, instance_type)

    # 查询镜像大小，动态计算系统盘大小
    # 如果已经提供了镜像大小（例如从 DescribeImageFromFamily 获取），直接使用
    if image_size_gb is None:
        # 否则查询镜像大小
        image_size_gb = get_image_size(region_id, image_id)
    else:
        print(f"Using provided image size: {image_size_gb}GB", file=sys.stderr)
    
    if image_size_gb:
        # 系统盘大小 = 镜像大小 + 10GB（用于安装工具和临时文件），最小 40GB
        system_disk_size = max(image_size_gb + 10, 40)
        print(f"Image size: {image_size_gb}GB, setting system disk size to {system_disk_size}GB", file=sys.stderr)
    else:
        # 如果查询失败，使用默认值 40GB（足够大多数镜像使用）
        system_disk_size = 40
        print(f"Failed to query image size, using default system disk size: {system_disk_size}GB", file=sys.stderr)

    cmd = [
        "aliyun",
        "ecs",
        "RunInstances",
        "--RegionId",
        region_id,
        "--ImageId",
        image_id,
        "--InstanceType",
        instance_type,
        "--SecurityGroupId",
        security_group_id,
        "--VSwitchId",
        vswitch_id,
        "--InstanceName",
        instance_name,
        "--InstanceChargeType",
        "PostPaid",
        "--SystemDisk.Category",
        system_disk_category,
        "--SystemDisk.Size",
        str(system_disk_size),
        "--SecurityEnhancementStrategy",
        "Deactive",
        "--UserData",
        user_data_b64,
    ]

    if key_pair_name:
        cmd.extend(["--KeyPairName", key_pair_name])

    if ram_role_name:
        cmd.extend(["--RamRoleName", ram_role_name])

    # 添加 Spot 策略和价格限制
    if spot_strategy == "SpotWithPriceLimit" and spot_price_limit:
        cmd.extend(
            [
                "--SpotStrategy",
                "SpotWithPriceLimit",
                "--SpotPriceLimit",
                spot_price_limit,
            ]
        )
    else:
        cmd.extend(["--SpotStrategy", "SpotAsPriceGo"])

    # 添加标签
    if tags:
        tag_index = 1
        for key, value in tags.items():
            cmd.extend([f"--Tag.{tag_index}.Key", key])
            cmd.extend([f"--Tag.{tag_index}.Value", value])
            tag_index += 1

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
        return result.returncode, result.stdout + result.stderr
    except (subprocess.SubprocessError, OSError) as e:
        return 1, str(e)


def get_vswitch_id(zone_id: str) -> Optional[str]:
    """根据可用区 ID 获取 VSwitch ID"""
    match = re.search(r"-([a-z])$", zone_id)
    if not match:
        return None

    zone_suffix = match.group(1).upper()
    vswitch_var = f"ALIYUN_VSWITCH_ID_{zone_suffix}"
    return os.environ.get(vswitch_var)


def extract_instance_id(response: str) -> Optional[str]:
    """从响应中提取实例 ID"""
    # 尝试从 JSON 响应中提取
    try:
        data = json.loads(response)
        if "InstanceIdSets" in data and "InstanceIdSet" in data["InstanceIdSets"]:
            instance_ids = data["InstanceIdSets"]["InstanceIdSet"]
            if instance_ids and len(instance_ids) > 0:
                return instance_ids[0]
    except (json.JSONDecodeError, KeyError, IndexError):
        pass

    # 尝试从文本中提取（格式：i-xxx）
    match = re.search(r"i-[a-z0-9]+", response)
    if match:
        return match.group(0)

    return None


def wait_for_instance_ready(
    region_id: str, instance_id: str, timeout: int = 600
) -> bool:
    """等待实例就绪"""
    print(f"Waiting for instance {instance_id} to be ready...", file=sys.stderr)
    start_time = time.time()

    while time.time() - start_time < timeout:
        cmd = [
            "aliyun",
            "ecs",
            "DescribeInstances",
            "--RegionId",
            region_id,
            "--InstanceIds",
            json.dumps([instance_id]),
        ]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=True, timeout=30
            )
            data = json.loads(result.stdout)

            if (
                "Instances" in data
                and "Instance" in data["Instances"]
                and len(data["Instances"]["Instance"]) > 0
            ):
                instance = data["Instances"]["Instance"][0]
                status = instance.get("Status", "")
                print(f"Instance status: {status}", file=sys.stderr)

                if status == "Running":
                    # 检查系统状态
                    system_status = instance.get("SystemEvent", {}).get("EventType", "")
                    if system_status != "SystemMaintenance.Reboot":
                        print("Instance is ready", file=sys.stderr)
                        return True

            time.sleep(10)
        except (subprocess.SubprocessError, json.JSONDecodeError, KeyError) as e:
            print(f"Error checking instance status: {e}", file=sys.stderr)
            time.sleep(10)

    print("Timeout waiting for instance to be ready", file=sys.stderr)
    return False


def wait_for_user_data_complete(
    region_id: str, instance_id: str, timeout: int = 1800
) -> bool:
    """等待 User Data 脚本执行完成"""
    print("Waiting for User Data script to complete...", file=sys.stderr)
    start_time = time.time()

    # 通过检查实例标签或元数据来判断（简化版本：等待固定时间后检查）
    # 实际应该通过 SSH 或实例元数据服务检查
    time.sleep(300)  # 等待 5 分钟，让脚本有时间执行

    print("User Data script should be complete", file=sys.stderr)
    return True


def create_image(
    region_id: str,
    instance_id: str,
    image_name: str,
    description: str,
    tags: Optional[dict] = None,
) -> Tuple[int, str]:
    """创建自定义镜像"""
    cmd = [
        "aliyun",
        "ecs",
        "CreateImage",
        "--RegionId",
        region_id,
        "--InstanceId",
        instance_id,
        "--ImageName",
        image_name,
        "--Description",
        description,
    ]

    if tags:
        tag_index = 1
        for key, value in tags.items():
            cmd.extend([f"--Tag.{tag_index}.Key", key])
            cmd.extend([f"--Tag.{tag_index}.Value", value])
            tag_index += 1

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
        return result.returncode, result.stdout + result.stderr
    except (subprocess.SubprocessError, OSError) as e:
        return 1, str(e)


def extract_image_id(response: str) -> Optional[str]:
    """从响应中提取镜像 ID"""
    try:
        data = json.loads(response)
        if "ImageId" in data:
            return data["ImageId"]
    except (json.JSONDecodeError, KeyError):
        pass

    # 尝试从文本中提取（格式：m-xxx）
    match = re.search(r"m-[a-z0-9]+", response)
    if match:
        return match.group(0)

    return None


def wait_for_image_ready(
    region_id: str, image_id: str, timeout: int = 3600
) -> bool:
    """等待镜像创建完成"""
    print(f"Waiting for image {image_id} to be ready...", file=sys.stderr)
    start_time = time.time()
    check_interval = 30
    consecutive_errors = 0
    max_consecutive_errors = 5

    while time.time() - start_time < timeout:
        # 尝试两种参数格式：直接字符串，或者 JSON 数组（虽然参数名是单数，但可能支持数组格式）
        success = False
        last_result = None
        for image_id_param in [image_id, json.dumps([image_id])]:
            cmd = [
                "aliyun",
                "ecs",
                "DescribeImages",
                "--RegionId",
                region_id,
                "--ImageId",
                image_id_param,
            ]

            try:
                result = subprocess.run(
                    cmd, capture_output=True, text=True, check=False, timeout=30
                )
                last_result = result

                # 即使返回码非零，也尝试解析输出（有时数据在 stdout）
                if result.stdout:
                    try:
                        data = json.loads(result.stdout)

                        if (
                            "Images" in data
                            and "Image" in data["Images"]
                            and len(data["Images"]["Image"]) > 0
                        ):
                            image = data["Images"]["Image"][0]
                            status = image.get("Status", "")
                            print(f"Image status: {status}", file=sys.stderr)

                            if status == "Available":
                                print("Image is ready", file=sys.stderr)
                                return True
                            elif status == "CreateFailed":
                                error_exit("Image creation failed")
                            
                            # 成功解析到镜像信息
                            success = True
                            consecutive_errors = 0
                            break
                    except json.JSONDecodeError:
                        # JSON 解析失败，继续尝试下一种格式
                        continue

                # 如果返回码为 0 但没有数据，可能是镜像还不存在，继续等待
                if result.returncode == 0:
                    success = True
                    consecutive_errors = 0
                    break

            except subprocess.TimeoutExpired:
                print("Command timeout, retrying...", file=sys.stderr)
                break
            except Exception as e:
                print(f"Unexpected error: {e}", file=sys.stderr)
                break

        # 如果所有格式都失败，记录错误但继续等待
        if not success:
            consecutive_errors += 1
            if last_result and last_result.returncode != 0:
                print(
                    f"Command failed with exit code {last_result.returncode}",
                    file=sys.stderr,
                )
                if last_result.stderr:
                    print(f"Error output: {last_result.stderr}", file=sys.stderr)
            
            # 如果连续多次错误，输出警告但继续等待
            if consecutive_errors >= max_consecutive_errors:
                print(
                    f"Warning: {consecutive_errors} consecutive errors, but continuing to wait...",
                    file=sys.stderr,
                )
                consecutive_errors = 0  # 重置计数，避免无限警告

        time.sleep(check_interval)

    print("Timeout waiting for image to be ready", file=sys.stderr)
    return False


def delete_instance(region_id: str, instance_id: str) -> bool:
    """删除实例"""
    print(f"Deleting instance {instance_id}...", file=sys.stderr)
    cmd = [
        "aliyun",
        "ecs",
        "DeleteInstance",
        "--RegionId",
        region_id,
        "--InstanceId",
        instance_id,
        "--Force",
        "true",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
        if result.returncode == 0:
            print("Instance deleted successfully", file=sys.stderr)
            return True
        else:
            print(f"Failed to delete instance: {result.stderr}", file=sys.stderr)
            return False
    except (subprocess.SubprocessError, OSError) as e:
        print(f"Error deleting instance: {e}", file=sys.stderr)
        return False


def check_existing_image(
    region_id: str, image_name_prefix: str, version_hash: str
) -> Optional[str]:
    """检查是否已存在相同版本的自定义镜像"""
    cmd = [
        "aliyun",
        "ecs",
        "DescribeImages",
        "--RegionId",
        region_id,
        "--ImageOwnerAlias",
        "self",
        "--ImageName",
        image_name_prefix,
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, timeout=30
        )
        data = json.loads(result.stdout)

        if (
            "Images" in data
            and "Image" in data["Images"]
            and len(data["Images"]["Image"]) > 0
        ):
            # 检查是否有匹配版本哈希的镜像
            for image in data["Images"]["Image"]:
                tags = image.get("Tags", {}).get("Tag", [])
                for tag in tags:
                    if tag.get("TagKey") == "VersionHash" and tag.get("TagValue") == version_hash:
                        image_id = image.get("ImageId", "")
                        print(f"Found existing image with matching version: {image_id}", file=sys.stderr)
                        return image_id

        return None
    except (subprocess.SubprocessError, json.JSONDecodeError, KeyError) as e:
        print(f"Error checking existing images: {e}", file=sys.stderr)
        return None


def list_images_by_name(
    region_id: str, image_name: str
) -> list:
    """列出指定名称的所有镜像（按创建时间排序）"""
    cmd = [
        "aliyun",
        "ecs",
        "DescribeImages",
        "--RegionId",
        region_id,
        "--ImageOwnerAlias",
        "self",
        "--ImageName",
        image_name,
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, timeout=30
        )
        data = json.loads(result.stdout)

        if (
            "Images" in data
            and "Image" in data["Images"]
            and len(data["Images"]["Image"]) > 0
        ):
            images = data["Images"]["Image"]
            # 按创建时间排序（最新的在前）
            images.sort(
                key=lambda x: x.get("CreationTime", ""), reverse=True
            )
            return images

        return []
    except (subprocess.SubprocessError, json.JSONDecodeError, KeyError) as e:
        print(f"Error listing images: {e}", file=sys.stderr)
        return []


def list_images_by_prefix(
    region_id: str, image_name_prefix: str
) -> list:
    """
    列出所有前缀匹配的镜像（包括 -latest 和日期时间后缀的）
    
    Args:
        region_id: 区域ID
        image_name_prefix: 镜像名称前缀（例如：github-runner-ubuntu24-amd64）
    
    Returns:
        所有匹配前缀的镜像列表（按创建时间排序，最新的在前）
    """
    import re
    
    # 查询所有自定义镜像（使用 ImageOwnerAlias=self）
    cmd = [
        "aliyun",
        "ecs",
        "DescribeImages",
        "--RegionId",
        region_id,
        "--ImageOwnerAlias",
        "self",
        "--PageSize",
        "100",  # 增加页面大小以获取更多镜像
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, timeout=30
        )
        data = json.loads(result.stdout)

        if (
            "Images" in data
            and "Image" in data["Images"]
            and len(data["Images"]["Image"]) > 0
        ):
            all_images = data["Images"]["Image"]
            
            # 筛选前缀匹配的镜像
            # 匹配规则：前缀 + "-latest" 或 前缀 + "-" + 日期时间（12位数字）
            pattern = re.compile(rf"^{re.escape(image_name_prefix)}(-latest|-(\d{{12}}))$")
            matched_images = []
            
            for image in all_images:
                image_name = image.get("ImageName", "")
                if pattern.match(image_name):
                    matched_images.append(image)
            
            # 按创建时间排序（最新的在前）
            matched_images.sort(
                key=lambda x: x.get("CreationTime", ""), reverse=True
            )
            
            return matched_images

        return []
    except (subprocess.SubprocessError, json.JSONDecodeError, KeyError) as e:
        print(f"Error listing images by prefix: {e}", file=sys.stderr)
        return []


def delete_image(region_id: str, image_id: str) -> bool:
    """删除镜像"""
    print(f"Deleting image {image_id}...", file=sys.stderr)
    cmd = [
        "aliyun",
        "ecs",
        "DeleteImage",
        "--RegionId",
        region_id,
        "--ImageId",
        image_id,
        "--Force",
        "true",
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=False, timeout=60
        )
        if result.returncode == 0:
            print(f"Image {image_id} deleted successfully", file=sys.stderr)
            return True
        else:
            print(f"Failed to delete image {image_id}: {result.stderr}", file=sys.stderr)
            return False
    except (subprocess.SubprocessError, OSError) as e:
        print(f"Error deleting image {image_id}: {e}", file=sys.stderr)
        return False


def modify_image_name(
    region_id: str, image_id: str, new_image_name: str
) -> bool:
    """修改镜像名称"""
    print(f"Renaming image {image_id} to {new_image_name}...", file=sys.stderr)
    cmd = [
        "aliyun",
        "ecs",
        "ModifyImageAttribute",
        "--RegionId",
        region_id,
        "--ImageId",
        image_id,
        "--ImageName",
        new_image_name,
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=False, timeout=60
        )
        if result.returncode == 0:
            print(f"Image {image_id} renamed to {new_image_name} successfully", file=sys.stderr)
            return True
        else:
            print(f"Failed to rename image {image_id}: {result.stderr}", file=sys.stderr)
            return False
    except (subprocess.SubprocessError, OSError) as e:
        print(f"Error renaming image {image_id}: {e}", file=sys.stderr)
        return False


def cleanup_old_images(
    region_id: str,
    image_name: str,
    keep_count: int = 5,
    exclude_image_id: Optional[str] = None,
) -> None:
    """
    清理旧版本镜像：重命名旧镜像并保留指定数量，删除多余的
    
    Args:
        region_id: 区域ID
        image_name: 镜像名称（应该以 -latest 结尾）
        keep_count: 保留的镜像数量
        exclude_image_id: 要排除的镜像ID（通常是新创建的镜像，不应被重命名）
    """
    from datetime import datetime
    
    images = list_images_by_name(region_id, image_name)
    
    if len(images) == 0:
        print(f"No existing images found with name {image_name}, no cleanup needed", file=sys.stderr)
        return
    
    # 按创建时间排序（最新的在前）
    images.sort(
        key=lambda x: x.get("CreationTime", ""), reverse=True
    )
    
    print(f"Found {len(images)} existing image(s) with name {image_name}", file=sys.stderr)
    
    # 重命名所有同名镜像（为新镜像让路）
    # 规则：如果镜像名称以 -latest 结尾，去掉 -latest 后加上日期后缀
    # 注意：排除新创建的镜像（exclude_image_id），它应该保持 -latest 后缀
    for image in images:
        image_id = image.get("ImageId", "")
        creation_time = image.get("CreationTime", "")
        image_name_display = image.get("ImageName", "")
        
        # 跳过要排除的镜像（通常是新创建的镜像）
        if exclude_image_id and image_id == exclude_image_id:
            print(f"Skipping newly created image {image_id} (keeping -latest suffix)", file=sys.stderr)
            continue
        
        # 只重命名名称完全匹配的镜像（即还是 -latest 的镜像）
        if image_name_display == image_name:
            # 解析创建时间，生成日期后缀
            try:
                # 阿里云时间格式：2024-01-01T12:00:00Z
                dt = datetime.fromisoformat(creation_time.replace("Z", "+00:00"))
                # 日期格式：YYYYMMDDHHMM（例如：202511192049）
                date_suffix = dt.strftime("%Y%m%d%H%M")
                
                # 去掉末尾的 -latest，然后加上日期后缀
                if image_name.endswith("-latest"):
                    base_name = image_name[:-7]  # 去掉 "-latest" (7个字符)
                    new_name = f"{base_name}-{date_suffix}"
                else:
                    # 如果不以 -latest 结尾，直接加上日期后缀
                    new_name = f"{image_name}-{date_suffix}"
                
                # 重命名镜像
                if modify_image_name(region_id, image_id, new_name):
                    print(f"Renamed image {image_id} from {image_name_display} to {new_name}", file=sys.stderr)
                else:
                    print(f"Warning: Failed to rename image {image_id}, will delete it instead", file=sys.stderr)
                    # 重命名失败，直接删除
                    delete_image(region_id, image_id)
            except (ValueError, AttributeError) as e:
                print(f"Warning: Failed to parse creation time {creation_time}: {e}, will delete image", file=sys.stderr)
                delete_image(region_id, image_id)
    
    # 提取镜像名称前缀（去掉 -latest 后缀）
    if image_name.endswith("-latest"):
        image_name_prefix = image_name[:-7]  # 去掉 "-latest" (7个字符)
    else:
        image_name_prefix = image_name
    
    # 查询所有前缀相同的镜像（包括 -latest 和日期时间后缀的）
    all_images_with_prefix = list_images_by_prefix(region_id, image_name_prefix)
    
    # 排除新创建的镜像（如果指定）
    if exclude_image_id:
        all_images_with_prefix = [img for img in all_images_with_prefix if img.get("ImageId") != exclude_image_id]
    
    # 统计总数
    total_count = len(all_images_with_prefix)
    print(f"Total images with prefix {image_name_prefix}: {total_count} (including -latest and date-suffixed)", file=sys.stderr)
    
    if total_count <= keep_count:
        print(f"Total image count ({total_count}) is within limit ({keep_count}), no deletion needed", file=sys.stderr)
        return
    
    # 按创建时间排序（最新的在前）
    all_images_with_prefix.sort(
        key=lambda x: x.get("CreationTime", ""), reverse=True
    )
    
    # 分离 -latest 镜像和日期时间后缀镜像
    latest_images = [img for img in all_images_with_prefix if img.get("ImageName", "").endswith("-latest")]
    dated_images = [img for img in all_images_with_prefix if not img.get("ImageName", "").endswith("-latest")]
    
    print(f"Found {len(latest_images)} -latest image(s) and {len(dated_images)} date-suffixed image(s)", file=sys.stderr)
    
    # 计算需要删除的数量
    # 保留策略：优先保留 -latest 镜像，然后保留最新的日期时间后缀镜像
    # 如果 -latest 镜像数量已经达到 keep_count，只删除日期时间后缀镜像
    # 否则，保留最新的 keep_count 个镜像（包括 -latest）
    
    if len(latest_images) >= keep_count:
        # 如果 -latest 镜像已经达到或超过保留数量，只保留最新的 keep_count 个 -latest 镜像
        # 删除所有日期时间后缀镜像和多余的 -latest 镜像
        images_to_keep = latest_images[:keep_count]
        images_to_delete = [img for img in all_images_with_prefix if img not in images_to_keep]
    else:
        # 保留所有 -latest 镜像，然后保留最新的日期时间后缀镜像，使总数不超过 keep_count
        remaining_slots = keep_count - len(latest_images)
        images_to_keep = latest_images + dated_images[:remaining_slots]
        images_to_delete = [img for img in all_images_with_prefix if img not in images_to_keep]
    
    print(f"Keeping {len(images_to_keep)} image(s), deleting {len(images_to_delete)} old one(s)", file=sys.stderr)
    
    # 删除多余的镜像（只删除日期时间后缀的镜像，不删除 -latest 镜像）
    for image in images_to_delete:
        image_id = image.get("ImageId", "")
        image_name_display = image.get("ImageName", "")
        creation_time = image.get("CreationTime", "")
        print(f"Deleting old image: {image_id} ({image_name_display}, created: {creation_time})", file=sys.stderr)
        delete_image(region_id, image_id)


def main():
    """主函数"""
    # 从环境变量获取参数
    region_id = get_env_var("ALIYUN_REGION_ID")
    vpc_id = get_env_var("ALIYUN_VPC_ID")
    security_group_id = get_env_var("ALIYUN_SECURITY_GROUP_ID")
    vswitch_id = os.environ.get("ALIYUN_VSWITCH_ID")
    instance_type = os.environ.get("INSTANCE_TYPE")
    image_name_prefix = get_env_var("IMAGE_NAME_PREFIX")
    arch = os.environ.get("ARCH", "amd64")
    key_pair_name = os.environ.get("ALIYUN_KEY_PAIR_NAME")
    ram_role_name = os.environ.get("ALIYUN_RAM_ROLE_NAME")
    spot_price_limit = os.environ.get("SPOT_PRICE_LIMIT")
    candidates_file = os.environ.get("CANDIDATES_FILE")

    # 验证架构参数
    if arch.lower() not in ("amd64", "arm64"):
        error_exit(f"ARCH must be either 'amd64' or 'arm64', got: {arch}")

    # 使用统一函数获取基础镜像信息
    base_image_info = get_base_image_info(region_id, arch)
    image_id = base_image_info["ImageId"]
    image_name = base_image_info.get("ImageName", "")
    image_creation_time = base_image_info.get("CreationTime", "")
    image_size_gb = base_image_info.get("Size")  # Size 字段单位是 GB（如果存在）
    
    print(f"Using base image: {image_id} ({image_name}, created: {image_creation_time})", file=sys.stderr)

    # 检查 Aliyun CLI 是否已安装
    try:
        subprocess.run(["aliyun", "--version"], capture_output=True, check=True)
    except (subprocess.SubprocessError, FileNotFoundError):
        error_exit(
            "Aliyun CLI is not installed or not in PATH. "
            "Please ensure aliyun-cli-setup-action is used in the workflow"
        )

    # 生成版本哈希
    version_hash = f"{image_id}_{image_creation_time}"
    
    # 检查是否已存在相同版本的镜像
    existing_image_id = check_existing_image(region_id, image_name_prefix, version_hash)
    if existing_image_id:
        print(f"IMAGE_ID={existing_image_id}", file=sys.stdout)
        print(f"SKIP_BUILD=true", file=sys.stdout)
        print("Image with matching version already exists, skipping build", file=sys.stderr)
        return

    # 创建 User Data 脚本
    user_data_script = create_user_data_script(arch)
    # 替换版本信息变量（在脚本中通过环境变量传递）
    user_data_script = user_data_script.replace("${BASE_IMAGE_ID}", image_id)
    user_data_script = user_data_script.replace("${BASE_IMAGE_NAME}", image_name)
    user_data_script = user_data_script.replace("${BASE_IMAGE_CREATION_TIME}", image_creation_time)
    
    # 编码 User Data
    user_data_b64 = base64.b64encode(user_data_script.encode("utf-8")).decode("ascii")

    # 生成实例名称
    timestamp = int(time.time())
    instance_name = f"image-builder-{arch}-{timestamp}"

    # 定义实例标签
    instance_tags = {
        "GIHUB_RUNNER_TYPE": "aliyun-ecs-spot",
    }

    # 创建临时实例（支持重试机制）
    instance_id = None
    if candidates_file and os.path.isfile(candidates_file):
        # 使用候选结果文件进行重试
        print(f"Using candidates file for retry mechanism: {candidates_file}", file=sys.stderr)
        with open(candidates_file, "r", encoding="utf-8") as f:
            candidates = [line.strip() for line in f if line.strip()]

        candidate_count = 0
        for candidate_line in candidates:
            candidate_count += 1
            parts = candidate_line.split("|")
            if len(parts) < 2:
                continue

            cand_instance_type = parts[0]
            cand_zone_id = parts[1] if len(parts) > 1 else ""
            cand_vswitch_id = parts[2] if len(parts) > 2 else vswitch_id
            cand_spot_price_limit = parts[3] if len(parts) > 3 else spot_price_limit

            if not cand_vswitch_id:
                # 尝试从可用区获取 VSwitch ID
                cand_vswitch_id = get_vswitch_id(cand_zone_id) if cand_zone_id else vswitch_id

            if not cand_vswitch_id:
                print(f"Skipping candidate {candidate_count}: No VSwitch ID", file=sys.stderr)
                continue

            print(f"Attempt {candidate_count}: Trying instance type {cand_instance_type} in zone {cand_zone_id}", file=sys.stderr)

            # 确定 Spot 策略
            spot_strategy = "SpotWithPriceLimit" if cand_spot_price_limit else "SpotAsPriceGo"

            # 创建实例（支持磁盘类型降级）
            disk_categories = ["cloud_essd", "cloud_ssd", "cloud_efficiency"]
            instance_created = False
            last_error = None

            for disk_category in disk_categories:
                print(
                    f"Attempting to create instance with disk category: {disk_category}",
                    file=sys.stderr,
                )
                exit_code, response = create_instance(
                    region_id=region_id,
                    image_id=image_id,
                    instance_type=cand_instance_type,
                    security_group_id=security_group_id,
                    vswitch_id=cand_vswitch_id,
                    instance_name=instance_name,
                    user_data_b64=user_data_b64,
                    key_pair_name=key_pair_name,
                    ram_role_name=ram_role_name,
                    spot_strategy=spot_strategy,
                    spot_price_limit=cand_spot_price_limit,
                    system_disk_category=disk_category,
                    tags=instance_tags,
                    image_size_gb=image_size_gb,
                )

                # 检查是否成功
                if exit_code == 0 and response:
                    candidate_instance_id = extract_instance_id(response)
                    if candidate_instance_id:
                        print(
                            f"Instance created successfully with disk category: {disk_category}",
                            file=sys.stderr,
                        )
                        instance_id = candidate_instance_id
                        instance_created = True
                        break
                    else:
                        # 尝试下一个磁盘类型
                        print(
                            f"Failed to extract instance ID, trying next disk category...",
                            file=sys.stderr,
                        )
                        last_error = response
                else:
                    # 记录错误信息，继续尝试下一个磁盘类型
                    last_error = response
                    if "InvalidSystemDiskCategory" in response or "not support" in response.lower():
                        print(
                            f"Disk category {disk_category} not supported, trying next...",
                            file=sys.stderr,
                        )
                    else:
                        # 其他错误，也继续尝试下一个磁盘类型（可能是临时错误）
                        print(
                            f"Failed to create instance with disk category {disk_category} (exit code: {exit_code}), trying next...",
                            file=sys.stderr,
                        )
                        if response:
                            # 只输出错误的前200个字符，避免日志过长
                            error_preview = response[:200] + ("..." if len(response) > 200 else "")
                            print(f"Error preview: {error_preview}", file=sys.stderr)

            if instance_created:
                break
            else:
                print(f"Failed to create instance (attempt {candidate_count}): All disk categories failed", file=sys.stderr)
                if last_error:
                    # 只输出错误的前200个字符，避免日志过长
                    error_preview = last_error[:200] + ("..." if len(last_error) > 200 else "")
                    print(f"Last error preview: {error_preview}", file=sys.stderr)

        if not instance_id:
            error_exit(f"Failed to create Spot instance after {candidate_count} attempts")
    else:
        # 没有候选结果文件，使用单次尝试
        if not instance_type:
            error_exit("INSTANCE_TYPE is required")
        if not vswitch_id:
            error_exit("ALIYUN_VSWITCH_ID is required")

        # 确定 Spot 策略
        spot_strategy = "SpotWithPriceLimit" if spot_price_limit else "SpotAsPriceGo"

        # 创建实例（支持磁盘类型降级）
        disk_categories = ["cloud_essd", "cloud_ssd", "cloud_efficiency"]
        instance_created = False
        last_error = None

        print(f"Creating temporary instance: {instance_name}", file=sys.stderr)
        for disk_category in disk_categories:
            print(
                f"Attempting to create instance with disk category: {disk_category}",
                file=sys.stderr,
            )
            exit_code, response = create_instance(
                region_id=region_id,
                image_id=image_id,
                instance_type=instance_type,
                security_group_id=security_group_id,
                vswitch_id=vswitch_id,
                instance_name=instance_name,
                user_data_b64=user_data_b64,
                key_pair_name=key_pair_name,
                ram_role_name=ram_role_name,
                spot_strategy=spot_strategy,
                spot_price_limit=spot_price_limit,
                system_disk_category=disk_category,
                tags=instance_tags,
                image_size_gb=image_size_gb,
            )

            # 检查是否成功
            if exit_code == 0 and response:
                instance_id = extract_instance_id(response)
                if instance_id:
                    print(
                        f"Instance created successfully with disk category: {disk_category}",
                        file=sys.stderr,
                    )
                    instance_created = True
                    break
                else:
                    # 尝试下一个磁盘类型
                    print(
                        f"Failed to extract instance ID, trying next disk category...",
                        file=sys.stderr,
                    )
                    last_error = response
            else:
                # 记录错误信息，继续尝试下一个磁盘类型
                last_error = response
                if "InvalidSystemDiskCategory" in response or "not support" in response.lower():
                    print(
                        f"Disk category {disk_category} not supported, trying next...",
                        file=sys.stderr,
                    )
                else:
                    # 其他错误，也继续尝试下一个磁盘类型（可能是临时错误）
                    print(
                        f"Failed to create instance with disk category {disk_category} (exit code: {exit_code}), trying next...",
                        file=sys.stderr,
                    )
                    if response:
                        # 只输出错误的前200个字符，避免日志过长
                        error_preview = response[:200] + ("..." if len(response) > 200 else "")
                        print(f"Error preview: {error_preview}", file=sys.stderr)

        # 所有磁盘类型都失败了
        if not instance_created:
            error_exit(
                f"Failed to create instance with all disk categories. Last error: {last_error}"
            )

        instance_id = extract_instance_id(response)
        if not instance_id:
            error_exit("Failed to extract instance ID from response")

        print(f"Instance created: {instance_id}", file=sys.stderr)

    # 确保清理实例（即使后续步骤失败）
    try:
        # 等待实例就绪
        if not wait_for_instance_ready(region_id, instance_id):
            error_exit("Instance failed to become ready")

        # 等待 User Data 脚本完成
        if not wait_for_user_data_complete(region_id, instance_id):
            error_exit("User Data script failed to complete")

        # 创建自定义镜像（使用固定名称，便于引用）
        # 命名规则：{prefix}-{arch}-latest（类似 Docker 的 ubuntu:latest）
        image_name_latest = f"{image_name_prefix}-{arch}-latest"
        
        # 在创建新镜像前，先处理旧镜像（重命名和清理）
        keep_count = int(os.environ.get("KEEP_IMAGE_COUNT", "5"))
        print(f"Processing existing images with name {image_name_latest} (keeping {keep_count} latest)", file=sys.stderr)
        cleanup_old_images(region_id, image_name_latest, keep_count, exclude_image_id=None)
        
        description = f"Custom Ubuntu 24 image for {arch} with pre-installed tools (base: {image_id})"
        tags = {
            "VersionHash": version_hash,
            "BaseImageId": image_id,
            "Architecture": arch,
            "BuildTimestamp": str(timestamp),
            "Latest": "true",  # 标记为最新版本
        }

        print(f"Creating custom image: {image_name_latest}", file=sys.stderr)
        exit_code, response = create_image(
            region_id=region_id,
            instance_id=instance_id,
            image_name=image_name_latest,
            description=description,
            tags=tags,
        )

        if exit_code != 0:
            error_exit(f"Failed to create image: {response}")

        image_id_new = extract_image_id(response)
        if not image_id_new:
            error_exit("Failed to extract image ID from response")

        print(f"Image created: {image_id_new}", file=sys.stderr)

        # 等待镜像就绪
        if not wait_for_image_ready(region_id, image_id_new):
            error_exit("Image failed to become ready")

        # 再次清理旧版本镜像（确保不超过保留数量）
        # 注意：排除新创建的镜像，它应该保持 -latest 后缀
        print(f"Final cleanup of old images (keeping {keep_count} latest)", file=sys.stderr)
        cleanup_old_images(region_id, image_name_latest, keep_count, exclude_image_id=image_id_new)

        # 输出结果
        print(f"IMAGE_ID={image_id_new}", file=sys.stdout)
        print(f"IMAGE_NAME={image_name_latest}", file=sys.stdout)
        print(f"SKIP_BUILD=false", file=sys.stdout)

    finally:
        # 清理临时实例（如果自毁机制失败，作为备用）
        # 注意：如果 RAM 角色配置正确，实例应该已经通过自毁机制删除
        if instance_id:
            print("Attempting to delete instance as fallback (self-destruct should have already done this)", file=sys.stderr)
            delete_instance(region_id, instance_id)


if __name__ == "__main__":
    main()

