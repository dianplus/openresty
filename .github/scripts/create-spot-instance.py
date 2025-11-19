#!/usr/bin/env python3
"""
创建阿里云 ECS Spot 实例
用于创建 Self-hosted Runner 实例
"""

import os
import sys
import subprocess
import base64
import json
import re
from typing import Optional, List, Tuple


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


def read_user_data(
    user_data_file: Optional[str] = None, user_data: Optional[str] = None
) -> Optional[str]:
    """读取 User Data"""
    if user_data_file and os.path.isfile(user_data_file):
        with open(user_data_file, "r", encoding="utf-8") as f:
            raw_data = f.read()
        # 规范化换行（去除 CRLF）
        user_data = raw_data.replace("\r\n", "\n").replace("\r", "\n")
        size = len(user_data.encode("utf-8"))
        print(
            f"Using User Data from file: {user_data_file} ({size} bytes, normalized)",
            file=sys.stderr,
        )
        return user_data
    elif user_data:
        # 规范化换行
        user_data = user_data.replace("\r\n", "\n").replace("\r", "\n")
        size = len(user_data.encode("utf-8"))
        print(
            f"Using User Data from environment variable ({size} bytes, normalized)",
            file=sys.stderr,
        )
        return user_data
    else:
        print("No User Data provided", file=sys.stderr)
        return None


def ensure_shebang(user_data: str) -> str:
    """确保 User Data 有 shebang"""
    if not user_data.startswith("#!"):
        print("User Data missing shebang; prepending #!/bin/bash", file=sys.stderr)
        return "#!/bin/bash\n" + user_data
    return user_data


def encode_user_data(user_data: str) -> str:
    """将 User Data 编码为 base64"""
    try:
        encoded = base64.b64encode(user_data.encode("utf-8")).decode("ascii")
        return encoded
    except (UnicodeEncodeError, UnicodeDecodeError) as e:
        error_exit(f"Failed to encode User Data to base64: {e}")


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
                    
                    if image_id:
                        print(f"Found latest image from family {image_family}: {image_id}", file=sys.stderr)
                        return {"ImageId": image_id}
            except json.JSONDecodeError as e:
                print(f"Warning: Failed to parse JSON response: {e}", file=sys.stderr)
                return None

        return None
    except Exception as e:
        print(f"Warning: Failed to query image from family {image_family}: {e}", file=sys.stderr)
        return None


def get_image_id(region_id: str, arch: str) -> str:
    """
    获取镜像 ID 的统一函数
    
    支持多种方式（按优先级）：
    1. 从镜像族系获取（ALIYUN_IMAGE_FAMILY）
    2. 从环境变量直接获取镜像 ID（ALIYUN_IMAGE_ID，向后兼容）
    
    返回镜像 ID
    """
    # 方式1：优先从镜像族系获取
    image_family = os.environ.get("ALIYUN_IMAGE_FAMILY")
    
    if image_family:
        print(f"Getting latest image from family: {image_family}", file=sys.stderr)
        image_info = get_image_from_family(region_id, image_family)
        
        if image_info and image_info.get("ImageId"):
            return image_info["ImageId"]
        else:
            print(f"Warning: Failed to get image from family {image_family}, falling back to ALIYUN_IMAGE_ID", file=sys.stderr)
    
    # 方式2：从环境变量直接获取镜像 ID（向后兼容）
    image_id = os.environ.get("ALIYUN_IMAGE_ID")
    
    if not image_id:
        error_exit(
            "Either ALIYUN_IMAGE_FAMILY or ALIYUN_IMAGE_ID must be set. "
            "If using ALIYUN_IMAGE_ID, it must be provided."
        )
    
    return image_id


def get_vswitch_id(zone_id: str) -> Optional[str]:
    """根据可用区 ID 获取 VSwitch ID"""
    match = re.search(r"-([a-z])$", zone_id)
    if not match:
        return None

    zone_suffix = match.group(1).upper()
    vswitch_var = f"ALIYUN_VSWITCH_ID_{zone_suffix}"
    return os.environ.get(vswitch_var)


def parse_candidates_file(
    candidates_file: str,
) -> List[Tuple[str, str, str, str, Optional[int]]]:
    """解析候选结果文件
    格式：INSTANCE_TYPE|ZONE_ID|VSWITCH_ID|SPOT_PRICE_LIMIT|CPU_CORES
    返回：(instance_type, zone_id, vswitch_id, spot_price_limit, cpu_cores)
    """
    candidates = []
    if not os.path.isfile(candidates_file):
        return candidates

    with open(candidates_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split("|")
            if len(parts) >= 4:
                instance_type = parts[0]
                zone_id = parts[1]
                vswitch_id = parts[2]
                spot_price_limit = parts[3]
                cpu_cores = int(parts[4]) if len(parts) > 4 and parts[4] else None
                candidates.append((instance_type, zone_id, vswitch_id, spot_price_limit, cpu_cores))

    return candidates


def calculate_spot_price_limit(
    price_per_core: Optional[float],
    cpu_cores: Optional[int],
    default_limit: Optional[str] = None,
) -> Optional[str]:
    """计算 Spot 价格限制"""
    if price_per_core and cpu_cores:
        total_price = price_per_core * cpu_cores
        spot_price_limit = total_price * 1.2
        return f"{spot_price_limit:.4f}"
    return default_limit


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
    key_pair_name: Optional[str] = None,
    ram_role_name: Optional[str] = None,
    spot_strategy: str = "SpotAsPriceGo",
    spot_price_limit: Optional[str] = None,
    user_data_b64: Optional[str] = None,
    system_disk_category: Optional[str] = None,
) -> Tuple[int, str]:
    """创建 ECS 实例"""
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
        "--SecurityEnhancementStrategy",
        "Deactive",
        "--Tag.1.Key",
        "GIHUB_RUNNER_TYPE",
        "--Tag.1.Value",
        "aliyun-ecs-spot",
    ]

    if key_pair_name:
        cmd.extend(["--KeyPairName", key_pair_name])

    if ram_role_name:
        cmd.extend(["--RamRoleName", ram_role_name])

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

    if user_data_b64:
        cmd.extend(["--UserData", user_data_b64])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        return result.returncode, result.stdout + result.stderr
    except (subprocess.SubprocessError, OSError) as e:
        return 1, str(e)


def extract_instance_id(response: str) -> Optional[str]:
    """从响应中提取实例 ID"""
    try:
        data = json.loads(response)
        if isinstance(data, dict):
            instance_id_sets = data.get("InstanceIdSets", {})
            if isinstance(instance_id_sets, dict):
                instance_id_set = instance_id_sets.get("InstanceIdSet", [])
                if isinstance(instance_id_set, list) and len(instance_id_set) > 0:
                    return instance_id_set[0]
    except (json.JSONDecodeError, KeyError, TypeError):
        pass

    # 使用正则表达式作为备选
    match = re.search(r'"InstanceId"\s*:\s*"([^"]+)"', response)
    if match:
        return match.group(1)

    return None


def main():
    """主函数"""
    # 从环境变量获取参数
    access_key_id = get_env_var("ALIYUN_ACCESS_KEY_ID")
    access_key_secret = get_env_var("ALIYUN_ACCESS_KEY_SECRET")
    region_id = get_env_var("ALIYUN_REGION_ID")
    vpc_id = get_env_var("ALIYUN_VPC_ID")
    security_group_id = get_env_var("ALIYUN_SECURITY_GROUP_ID")
    vswitch_id = os.environ.get("ALIYUN_VSWITCH_ID")
    key_pair_name = os.environ.get("ALIYUN_KEY_PAIR_NAME")
    ram_role_name = os.environ.get("ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME")
    instance_type = os.environ.get("INSTANCE_TYPE")
    instance_name = get_env_var("INSTANCE_NAME")
    user_data_file = os.environ.get("USER_DATA_FILE")
    user_data = os.environ.get("USER_DATA")
    arch = os.environ.get("ARCH", "amd64")
    spot_price_limit = os.environ.get("SPOT_PRICE_LIMIT")
    candidates_file = os.environ.get("CANDIDATES_FILE")
    
    # 使用统一函数获取镜像 ID（支持镜像族系）
    image_id = get_image_id(region_id, arch)

    # 配置 Aliyun CLI 环境变量
    os.environ["ALIBABA_CLOUD_ACCESS_KEY_ID"] = access_key_id
    os.environ["ALIBABA_CLOUD_ACCESS_KEY_SECRET"] = access_key_secret

    # 验证 Aliyun CLI 是否已安装
    try:
        subprocess.run(["aliyun", "--version"], capture_output=True, check=True)
    except (subprocess.SubprocessError, FileNotFoundError):
        error_exit(
            "Aliyun CLI is not installed or not in PATH. "
            "Please ensure aliyun-cli-setup-action is used in the workflow"
        )
    
    # 验证 Aliyun CLI 配置
    print("Verifying Aliyun CLI configuration...", file=sys.stderr)
    try:
        subprocess.run(
            ["aliyun", "configure", "get"],
            capture_output=True,
            check=False
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        print("Warning: Aliyun CLI configuration check failed, but continuing...", file=sys.stderr)

    # 读取 User Data
    user_data_content = read_user_data(user_data_file, user_data)
    if user_data_content:
        user_data_content = ensure_shebang(user_data_content)

    print("=== Creating Spot Instance ===", file=sys.stderr)
    print(f"Instance Name: {instance_name}", file=sys.stderr)
    print(f"Instance Type: {instance_type}", file=sys.stderr)
    print(f"Region: {region_id}", file=sys.stderr)
    print(f"Architecture: {arch}", file=sys.stderr)
    print(f"VPC ID: {vpc_id}", file=sys.stderr)
    print(f"VSwitch ID: {vswitch_id}", file=sys.stderr)
    print(f"Security Group ID: {security_group_id}", file=sys.stderr)
    print(f"Image ID: {image_id}", file=sys.stderr)
    if key_pair_name:
        print(f"Key Pair Name: {key_pair_name}", file=sys.stderr)
    if spot_price_limit:
        print(f"Spot Price Limit: {spot_price_limit}", file=sys.stderr)

    # 实现重试机制（如果有候选结果文件）
    if candidates_file and os.path.isfile(candidates_file):
        candidates = parse_candidates_file(candidates_file)
        candidate_count = len(candidates)
        print(f"Found {candidate_count} candidate instances for retry", file=sys.stderr)

        # 尝试每个候选结果
        for attempt, (
            cand_instance_type,
            cand_zone_id,
            cand_vswitch_id,
            cand_spot_price_limit,
            _cand_cpu_cores,  # 保留在元组中但不使用
        ) in enumerate(candidates, 1):
            # VSwitch ID 和 Spot Price Limit 已经从候选文件中读取，无需重复计算
            if not cand_vswitch_id:
                print(
                    f"Warning: VSwitch ID is empty for candidate {attempt}, skipping",
                    file=sys.stderr,
                )
                continue

            print(
                f"Attempt {attempt}/{candidate_count}: Trying instance type {cand_instance_type} in zone {cand_zone_id}",
                file=sys.stderr,
            )

            # 编码 User Data
            user_data_b64 = None
            if user_data_content:
                user_data_b64 = encode_user_data(user_data_content)

            # 确定 Spot 策略
            spot_strategy = (
                "SpotWithPriceLimit" if cand_spot_price_limit else "SpotAsPriceGo"
            )

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
                    key_pair_name=key_pair_name,
                    ram_role_name=ram_role_name,
                    spot_strategy=spot_strategy,
                    spot_price_limit=cand_spot_price_limit,
                    user_data_b64=user_data_b64,
                    system_disk_category=disk_category,
                )

                # 检查是否成功
                if exit_code == 0 and response:
                    instance_id = extract_instance_id(response)
                    if instance_id and instance_id != "null":
                        print(
                            f"Spot instance created successfully on attempt {attempt} with disk category: {disk_category}",
                            file=sys.stderr,
                        )
                        print(f"Instance Type: {cand_instance_type}", file=sys.stderr)
                        print(f"Zone: {cand_zone_id}", file=sys.stderr)
                        print(f"VSwitch: {cand_vswitch_id}", file=sys.stderr)
                        instance_created = True
                        print(instance_id)
                        sys.exit(0)
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

            # 如果所有磁盘类型都失败了，记录错误并继续下一个候选
            if not instance_created:
                print(f"Attempt {attempt} failed: All disk categories failed", file=sys.stderr)
                if response:
                    print(f"Response: {response[:500]}...", file=sys.stderr)

        # 所有候选结果都失败了
        error_exit(f"Failed to create Spot instance after {candidate_count} attempts")
    else:
        # 没有候选结果文件，使用原始逻辑（单次尝试）
        if not instance_type:
            error_exit("INSTANCE_TYPE is required")

        if not vswitch_id:
            error_exit("ALIYUN_VSWITCH_ID is required")

        # 编码 User Data
        user_data_b64 = None
        if user_data_content:
            user_data_b64 = encode_user_data(user_data_content)

        # 确定 Spot 策略
        spot_strategy = "SpotWithPriceLimit" if spot_price_limit else "SpotAsPriceGo"

        # 构建命令显示（不包含 UserData）
        cmd_display = f"aliyun ecs RunInstances --RegionId {region_id} --ImageId {image_id} --InstanceType {instance_type} ..."
        if user_data_b64:
            cmd_display += " --UserData <base64-encoded-data>"
        print(f"Executing command: {cmd_display}", file=sys.stderr)
        print("About to execute Aliyun CLI command...", file=sys.stderr)

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
                instance_type=instance_type,
                security_group_id=security_group_id,
                vswitch_id=vswitch_id,
                instance_name=instance_name,
                key_pair_name=key_pair_name,
                ram_role_name=ram_role_name,
                spot_strategy=spot_strategy,
                spot_price_limit=spot_price_limit,
                user_data_b64=user_data_b64,
                system_disk_category=disk_category,
            )

            # 检查是否成功
            if exit_code == 0 and response:
                instance_id = extract_instance_id(response)
                if instance_id and instance_id != "null":
                    print(
                        f"Instance created successfully with disk category: {disk_category}",
                        file=sys.stderr,
                    )
                    instance_created = True
                    print(instance_id)
                    sys.exit(0)
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
                f"Failed to create Spot instance with all disk categories. Last error: {last_error}"
            )


if __name__ == "__main__":
    main()
