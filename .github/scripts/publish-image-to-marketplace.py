#!/usr/bin/env python3
"""
发布镜像到阿里云镜像市场
支持公开或私有发布
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


def modify_image_share_permission(
    region_id: str,
    image_id: str,
    add_account_ids: Optional[list] = None,
    remove_account_ids: Optional[list] = None,
) -> bool:
    """修改镜像共享权限"""
    cmd = [
        "aliyun",
        "ecs",
        "ModifyImageSharePermission",
        "--RegionId",
        region_id,
        "--ImageId",
        image_id,
    ]

    if add_account_ids:
        cmd.extend(["--AddAccount", json.dumps(add_account_ids)])
    if remove_account_ids:
        cmd.extend(["--RemoveAccount", json.dumps(remove_account_ids)])

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, timeout=60
        )
        print(f"Image share permission modified successfully", file=sys.stderr)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to modify image share permission: {e.stderr}", file=sys.stderr)
        return False
    except (subprocess.SubprocessError, OSError) as e:
        print(f"Error modifying image share permission: {e}", file=sys.stderr)
        return False


def publish_to_marketplace(
    region_id: str,
    image_id: str,
    image_name: str,
    description: str,
    is_public: bool = False,
) -> bool:
    """发布镜像到镜像市场（公开或私有）"""
    # 注意：阿里云镜像市场的发布需要通过控制台或专门的 API
    # 这里提供一个基础框架，实际实现可能需要使用镜像市场 API

    print(f"Publishing image {image_id} to marketplace...", file=sys.stderr)
    print(f"Image name: {image_name}", file=sys.stderr)
    print(f"Description: {description}", file=sys.stderr)
    print(f"Public: {is_public}", file=sys.stderr)

    # 如果公开，需要修改镜像共享权限为公开
    if is_public:
        # 注意：公开镜像需要特殊权限和审核流程
        # 这里仅作为示例，实际需要根据阿里云镜像市场的具体 API 实现
        print("Warning: Public image publishing requires special permissions and review process", file=sys.stderr)
        print("This is a placeholder implementation", file=sys.stderr)
        return False

    # 私有发布：保持镜像为私有，仅共享给特定账号
    print("Image will remain private (not published to public marketplace)", file=sys.stderr)
    return True


def main():
    """主函数"""
    # 从环境变量获取参数
    region_id = get_env_var("ALIYUN_REGION_ID")
    image_id = get_env_var("IMAGE_ID")
    image_name = os.environ.get("IMAGE_NAME", "")
    description = os.environ.get("IMAGE_DESCRIPTION", "")
    is_public = os.environ.get("PUBLISH_PUBLIC", "false").lower() == "true"
    share_account_ids = os.environ.get("SHARE_ACCOUNT_IDS", "")

    # 检查 Aliyun CLI 是否已安装
    try:
        subprocess.run(["aliyun", "--version"], capture_output=True, check=True)
    except (subprocess.SubprocessError, FileNotFoundError):
        error_exit(
            "Aliyun CLI is not installed or not in PATH. "
            "Please ensure aliyun-cli-setup-action is used in the workflow"
        )

    # 如果指定了共享账号，修改镜像共享权限
    if share_account_ids:
        account_ids = [aid.strip() for aid in share_account_ids.split(",") if aid.strip()]
        if account_ids:
            print(f"Sharing image with accounts: {account_ids}", file=sys.stderr)
            if not modify_image_share_permission(
                region_id=region_id,
                image_id=image_id,
                add_account_ids=account_ids,
            ):
                error_exit("Failed to share image with specified accounts")

    # 发布到镜像市场（如果需要）
    if is_public:
        if not publish_to_marketplace(
            region_id=region_id,
            image_id=image_id,
            image_name=image_name,
            description=description,
            is_public=True,
        ):
            error_exit("Failed to publish image to marketplace")

    print(f"Image {image_id} published successfully", file=sys.stderr)
    print(f"IMAGE_ID={image_id}", file=sys.stdout)


if __name__ == "__main__":
    main()

