#!/usr/bin/env python3
"""
查询阿里云 Ubuntu 24 最新镜像
支持 AMD64 和 ARM64 架构筛选
"""

import json
import os
import re
import subprocess
import sys
from typing import Optional


def error_exit(message: str) -> None:
    """输出错误信息并退出"""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def get_env_var(name: str) -> str:
    """从环境变量获取值，如果不存在则报错"""
    value = os.environ.get(name)
    if not value:
        error_exit(f"{name} is required")
    return value


def query_images(
    region_id: str,
    architecture: str,  # x86_64 或 arm64
) -> Optional[list]:
    """查询 Ubuntu 24 镜像"""
    # 映射架构名称
    arch_map = {
        "amd64": "x86_64",
        "arm64": "arm64",
    }
    aliyun_arch = arch_map.get(architecture.lower(), architecture)

    # 构建查询命令
    cmd = [
        "aliyun",
        "ecs",
        "DescribeImages",
        "--RegionId",
        region_id,
        "--ImageOwnerAlias",
        "system",
        "--Architecture",
        aliyun_arch,
        "--Status",
        "Available",
        "--PageSize",
        "100",
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, timeout=30
        )
        data = json.loads(result.stdout)

        if "Images" not in data or "Image" not in data["Images"]:
            return None

        images = data["Images"]["Image"]
        if not images:
            return None

        # 筛选 Ubuntu 24 镜像
        ubuntu24_images = []
        for image in images:
            image_name = image.get("ImageName", "")
            # 匹配 Ubuntu 24 相关镜像名称
            if re.search(r"ubuntu.*24|Ubuntu.*24", image_name, re.IGNORECASE):
                ubuntu24_images.append(image)

        if not ubuntu24_images:
            return None

        # 按创建时间排序（最新的在前）
        ubuntu24_images.sort(key=lambda x: x.get("CreationTime", ""), reverse=True)

        return ubuntu24_images

    except subprocess.TimeoutExpired:
        print("Warning: Query timeout", file=sys.stderr)
        return None
    except subprocess.CalledProcessError as e:
        print(f"Warning: Query failed: {e}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"Warning: Failed to parse JSON: {e}", file=sys.stderr)
        return None


def main():
    """主函数"""
    # 从环境变量获取参数
    region_id = get_env_var("ALIYUN_REGION_ID")
    arch = os.environ.get("ARCH", "amd64")

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

    # 查询镜像
    images = query_images(region_id, arch)

    if not images:
        error_exit(
            f"No Ubuntu 24 images found for architecture {arch} in region {region_id}"
        )

    # 获取最新镜像
    latest_image = images[0]

    # 输出结果（用于 GitHub Actions 捕获）
    print(f"IMAGE_ID={latest_image.get('ImageId', '')}")
    print(f"IMAGE_NAME={latest_image.get('ImageName', '')}")
    print(f"CREATION_TIME={latest_image.get('CreationTime', '')}")
    print(f"ARCHITECTURE={latest_image.get('Architecture', '')}")
    print(f"SIZE={latest_image.get('Size', 0)}")

    # 生成版本标识（基于镜像 ID 和创建时间）
    image_id = latest_image.get("ImageId", "")
    creation_time = latest_image.get("CreationTime", "")
    version_hash = f"{image_id}_{creation_time}"
    print(f"VERSION_HASH={version_hash}")

    # 输出调试信息到标准错误
    print("Latest Ubuntu 24 image found:", file=sys.stderr)
    print(f"  Image ID: {image_id}", file=sys.stderr)
    print(f"  Image Name: {latest_image.get('ImageName', '')}", file=sys.stderr)
    print(f"  Creation Time: {creation_time}", file=sys.stderr)
    print(f"  Architecture: {latest_image.get('Architecture', '')}", file=sys.stderr)
    print(f"  Version Hash: {version_hash}", file=sys.stderr)


if __name__ == "__main__":
    main()
