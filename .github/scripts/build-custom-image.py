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
cat > "${{VERSION_FILE}}" << 'VERSION_EOF'
{{
  "base_image": "BASE_IMAGE_ID_PLACEHOLDER",
  "base_image_name": "BASE_IMAGE_NAME_PLACEHOLDER",
  "base_image_creation_time": "BASE_IMAGE_CREATION_TIME_PLACEHOLDER",
  "aliyun_cli_version": "${{ALIYUN_CLI_VERSION}}",
  "advisor_version": "${{ADVISOR_VERSION}}",
  "runner_version": "${{RUNNER_VERSION}}",
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
) -> Tuple[int, str]:
    """创建 ECS Spot 实例"""
    # 如果没有指定磁盘类型，自动检测
    if not system_disk_category:
        system_disk_category = get_supported_disk_category(region_id, instance_type)

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
        "20",  # 20GB 系统盘（最小值，足够安装工具）
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
        # 尝试两种参数格式：先尝试 JSON 数组，失败则尝试逗号分隔字符串
        success = False
        last_result = None
        for image_ids_param in [json.dumps([image_id]), image_id]:
            cmd = [
                "aliyun",
                "ecs",
                "DescribeImages",
                "--RegionId",
                region_id,
                "--ImageIds",
                image_ids_param,
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


def cleanup_old_images(
    region_id: str,
    image_name: str,
    keep_count: int = 1,
) -> None:
    """清理旧版本镜像，只保留指定数量的最新版本"""
    images = list_images_by_name(region_id, image_name)
    
    if len(images) <= keep_count:
        print(f"Only {len(images)} image(s) found, no cleanup needed (keeping {keep_count})", file=sys.stderr)
        return

    # 删除超出保留数量的旧镜像
    images_to_delete = images[keep_count:]
    print(f"Found {len(images)} images, keeping {keep_count} latest, deleting {len(images_to_delete)} old ones", file=sys.stderr)
    
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
    image_id = get_env_var("BASE_IMAGE_ID")
    image_name = get_env_var("BASE_IMAGE_NAME", "")
    image_creation_time = get_env_var("BASE_IMAGE_CREATION_TIME", "")
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
                else:
                    # 检查错误信息，如果是磁盘类型不支持，尝试下一个
                    if "InvalidSystemDiskCategory" in response or "not support" in response.lower():
                        print(
                            f"Disk category {disk_category} not supported, trying next...",
                            file=sys.stderr,
                        )
                        continue
                    else:
                        # 其他错误，不继续尝试
                        break

            if instance_created:
                break
            else:
                print(f"Failed to create instance (attempt {candidate_count}): All disk categories failed", file=sys.stderr)

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
                # 检查错误信息，如果是磁盘类型不支持，尝试下一个
                if "InvalidSystemDiskCategory" in response or "not support" in response.lower():
                    print(
                        f"Disk category {disk_category} not supported, trying next...",
                        file=sys.stderr,
                    )
                    last_error = response
                    continue
                else:
                    # 其他错误，不继续尝试
                    last_error = response
                    break

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

        # 清理旧版本镜像（只保留最新版本）
        keep_count = int(os.environ.get("KEEP_IMAGE_COUNT", "1"))
        cleanup_old_images(region_id, image_name_latest, keep_count)

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

