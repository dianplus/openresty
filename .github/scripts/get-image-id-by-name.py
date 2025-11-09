#!/usr/bin/env python3
"""
通过镜像名称查找镜像 ID
类似 Docker 的 `ubuntu:latest` 引用方式
"""

import json
import os
import subprocess
import sys
from typing import Optional


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


def get_image_id_by_name(
    region_id: str,
    image_name: str,
    architecture: Optional[str] = None,
) -> Optional[str]:
    """通过镜像名称查找镜像 ID"""
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

    if architecture:
        # 映射架构名称
        arch_map = {
            "amd64": "x86_64",
            "arm64": "arm64",
        }
        aliyun_arch = arch_map.get(architecture.lower(), architecture)
        cmd.extend(["--Architecture", aliyun_arch])

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
            
            # 如果有多个镜像，按创建时间排序（最新的在前）
            if len(images) > 1:
                images.sort(
                    key=lambda x: x.get("CreationTime", ""), reverse=True
                )
            
            # 返回第一个（最新的）镜像 ID
            image_id = images[0].get("ImageId", "")
            if image_id:
                return image_id

        return None
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
    image_name = get_env_var("IMAGE_NAME")
    architecture = os.environ.get("ARCH")  # 可选，用于筛选架构

    # 检查 Aliyun CLI 是否已安装
    try:
        subprocess.run(["aliyun", "--version"], capture_output=True, check=True)
    except (subprocess.SubprocessError, FileNotFoundError):
        error_exit(
            "Aliyun CLI is not installed or not in PATH. "
            "Please ensure aliyun-cli-setup-action is used in the workflow"
        )

    # 查询镜像 ID
    image_id = get_image_id_by_name(region_id, image_name, architecture)

    if not image_id:
        error_exit(
            f"Image not found: {image_name}"
            + (f" (architecture: {architecture})" if architecture else "")
        )

    # 输出结果（用于 GitHub Actions 捕获）
    print(f"IMAGE_ID={image_id}", file=sys.stdout)
    
    # 输出调试信息到标准错误
    print(f"Found image: {image_name}", file=sys.stderr)
    print(f"  Image ID: {image_id}", file=sys.stderr)
    if architecture:
        print(f"  Architecture: {architecture}", file=sys.stderr)


if __name__ == "__main__":
    main()

