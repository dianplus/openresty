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
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        
        # Parse response (might be JSON or table format)
        response_text = result.stdout.strip()
        
        # Try parsing as JSON
        if response_text.startswith("{") or response_text.startswith("["):
            try:
                response = json.loads(response_text)
                instances = response.get("Instances", {}).get("Instance", [])
                if instances:
                    return instances[0].get("Status")
            except json.JSONDecodeError:
                pass
        
        # If not JSON, try to extract status using regex or other methods
        # For now, return None if not JSON format
        return None
            
    except subprocess.CalledProcessError as e:
        log_error(f"Failed to query instance status: {e}")
        log_error(f"Error output: {e.stderr}")
        return None
    except json.JSONDecodeError as e:
        log_error(f"Failed to parse response: {e}")
        return None


def get_instance_details(instance_id: str) -> Optional[dict]:
    """Get detailed instance information."""
    cmd = [
        "aliyun",
        "ecs",
        "DescribeInstances",
        "--InstanceIds", json.dumps([instance_id]),
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        
        response_text = result.stdout.strip()
        if response_text.startswith("{") or response_text.startswith("["):
            response = json.loads(response_text)
            instances = response.get("Instances", {}).get("Instance", [])
            if instances:
                return instances[0]
    except Exception:
        pass
    
    return None


def wait_for_instance_ready(instance_id: str, max_wait: int = 600, sleep_interval: int = 10) -> bool:
    """Wait for instance to be ready."""
    log_info(f"Waiting for instance {instance_id} to be ready...")
    log_info(f"Maximum wait time: {max_wait}s")
    log_info("Log files location (once instance is running):")
    log_info("  - User Data: /var/log/user-data.log")
    log_info("  - Setup Script: /var/log/github-runner/setup.log")
    log_info("  - Runner: /var/log/github-runner/runner.log")
    print()
    
    elapsed = 0
    instance_details = None
    
    while elapsed < max_wait:
        status = get_instance_status(instance_id)
        
        if status is None:
            log_warning(f"Could not get instance status (elapsed: {elapsed}s)")
        else:
            log_info(f"Instance status: {status} (elapsed: {elapsed}s)")
            
            if status == "Running":
                log_success("Instance is running")
                
                # Get instance details for log viewing instructions
                instance_details = get_instance_details(instance_id)
                if instance_details:
                    instance_name = instance_details.get("InstanceName", "N/A")
                    public_ip = instance_details.get("PublicIpAddress", {}).get("IpAddress", [])
                    
                    print()
                    log_info("Runner setup is in progress. To monitor setup:")
                    log_info("1. Check GitHub Actions runner registration:")
                    log_info(f"   Runner name pattern: {instance_name}")
                    
                    if public_ip:
                        ip = public_ip[0] if isinstance(public_ip, list) else public_ip
                        log_info("2. SSH to instance (if accessible):")
                        log_info(f"   ssh root@{ip}")
                        log_info("   tail -f /var/log/user-data.log")
                        log_info("   tail -f /var/log/github-runner/setup.log")
                    else:
                        log_info("2. Use Aliyun Console Cloud Assistant to view logs")
                        log_info("   Or configure VPC connection for SSH access")
                    
                    log_info("3. Use check-runner-status.py script:")
                    log_info(f"   python3 .github/scripts/check-runner-status.py {instance_id}")
                
                return True
            elif status in ("Stopped", "Stopping"):
                log_error(f"Instance failed to start (status: {status})")
                return False
        
        time.sleep(sleep_interval)
        elapsed += sleep_interval
    
    log_error(f"Timeout waiting for instance to be ready (waited {max_wait}s)")
    if instance_details:
        log_info("Instance may still be starting. Check logs for details.")
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

