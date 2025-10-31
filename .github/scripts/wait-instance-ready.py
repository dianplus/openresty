#!/usr/bin/env python3
"""
Wait for ECS instance to be ready (Running status).

Usage: ./wait-instance-ready.py <instance-id> [max-wait-seconds]
Default max wait: 600 seconds (10 minutes)
"""

import json
import os
import subprocess
import sys
import time
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


def log_warning(msg: str) -> None:
    """Print warning message."""
    print(f"⚠️  {msg}")


def get_instance_status(instance_id: str) -> Optional[str]:
    """Get ECS instance status."""
    cmd = [
        "aliyun",
        "ecs",
        "DescribeInstances",
        "--InstanceIds", json.dumps([instance_id]),
        "--Output", "json",
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        
        response = json.loads(result.stdout)
        instances = response.get("Instances", {}).get("Instance", [])
        
        if instances:
            return instances[0].get("Status")
        else:
            return None
            
    except subprocess.CalledProcessError as e:
        log_error(f"Failed to query instance status: {e}")
        log_error(f"Error output: {e.stderr}")
        return None
    except json.JSONDecodeError as e:
        log_error(f"Failed to parse response: {e}")
        return None


def wait_for_instance_ready(instance_id: str, max_wait: int = 600, sleep_interval: int = 10) -> bool:
    """Wait for instance to be ready."""
    log_info(f"Waiting for instance {instance_id} to be ready...")
    log_info(f"Maximum wait time: {max_wait}s")
    
    elapsed = 0
    
    while elapsed < max_wait:
        status = get_instance_status(instance_id)
        
        if status is None:
            log_warning(f"Could not get instance status (elapsed: {elapsed}s)")
        else:
            log_info(f"Instance status: {status} (elapsed: {elapsed}s)")
            
            if status == "Running":
                log_success("Instance is running")
                return True
            elif status in ("Stopped", "Stopping"):
                log_error(f"Instance failed to start (status: {status})")
                return False
        
        time.sleep(sleep_interval)
        elapsed += sleep_interval
    
    log_error(f"Timeout waiting for instance to be ready (waited {max_wait}s)")
    return False


def main():
    """Main function."""
    if len(sys.argv) < 2:
        log_error(f"Usage: {sys.argv[0]} <instance-id> [max-wait-seconds]")
        sys.exit(1)
    
    instance_id = sys.argv[1]
    max_wait = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    
    success = wait_for_instance_ready(instance_id, max_wait)
    
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()

