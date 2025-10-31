#!/usr/bin/env python3
"""
Cleanup (delete) an ECS instance.

Usage: ./cleanup-instance.py <instance-id> [force]
Default force: true
"""

import subprocess
import sys
from typing import Optional


def log_info(msg: str) -> None:
    """Print info message."""
    print(f"ℹ️  {msg}")


def log_success(msg: str) -> None:
    """Print success message."""
    print(f"✅ {msg}")


def log_error(msg: str) -> None:
    """Print error message."""
    print(f"❌ {msg}")


def delete_instance(instance_id: str, force: bool = True) -> bool:
    """Delete ECS instance."""
    cmd = [
        "aliyun",
        "ecs",
        "DeleteInstance",
        "--InstanceId", instance_id,
        "--Force", str(force).lower(),
    ]
    
    try:
        subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        log_error(f"Failed to delete instance: {e}")
        log_error(f"Error output: {e.stderr}")
        return False


def main():
    """Main function."""
    if len(sys.argv) < 2:
        log_error(f"Usage: {sys.argv[0]} <instance-id> [force]")
        sys.exit(1)
    
    instance_id = sys.argv[1]
    force = sys.argv[2].lower() == "true" if len(sys.argv) > 2 else True
    
    log_info(f"Cleaning up instance: {instance_id}")
    log_info(f"Force delete: {force}")
    
    success = delete_instance(instance_id, force)
    
    if success:
        log_success("Instance cleaned up successfully")
    else:
        log_error("Failed to cleanup instance")
        sys.exit(1)


if __name__ == "__main__":
    main()

