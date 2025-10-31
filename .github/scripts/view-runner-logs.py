#!/usr/bin/env python3
"""
View runner setup logs from ECS instance.

Usage: ./view-runner-logs.py <instance-id> [log-file]
Default log file: /var/log/user-data.log or /root/runner.log
"""

import json
import os
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


def get_instance_info(instance_id: str) -> Optional[dict]:
    """Get ECS instance information."""
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
    except Exception as e:
        log_error(f"Failed to get instance info: {e}")
    
    return None


def get_instance_logs_via_cloud_assistant(instance_id: str, log_file: str = "/var/log/user-data.log") -> Optional[str]:
    """Try to get logs via Aliyun Cloud Assistant (if available)."""
    # This is a placeholder - Aliyun Cloud Assistant commands vary
    # For now, we'll use SSH as the primary method
    return None


def get_instance_logs_via_ssh(instance_id: str, log_file: str) -> Optional[str]:
    """Get logs via SSH (requires SSH key configured)."""
    # Get instance public IP
    instance_info = get_instance_info(instance_id)
    if not instance_info:
        return None
    
    public_ip = instance_info.get("PublicIpAddress", {}).get("IpAddress", [])
    if not public_ip:
        log_error("Instance has no public IP address")
        return None
    
    ip = public_ip[0] if isinstance(public_ip, list) else public_ip
    
    # Try to SSH and get logs
    # Note: This requires SSH access configured
    log_info(f"Attempting to fetch logs from {ip}:{log_file}")
    
    # Use aliyun CLI exec command if available, or suggest manual SSH
    cmd = [
        "aliyun",
        "ecs",
        "InvokeCommand",
        "--InstanceId", instance_id,
        "--CommandContent", f"cat {log_file}",
        "--Type", "RunShellScript",
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        # Parse response and extract output
        # This depends on Aliyun Cloud Assistant API
        return result.stdout
    except Exception:
        # Cloud Assistant might not be available
        log_info("Cloud Assistant not available, manual SSH required")
        log_info(f"To view logs manually, SSH to the instance:")
        log_info(f"  ssh root@{ip}")
        log_info(f"  cat {log_file}")
        return None


def main():
    """Main function."""
    if len(sys.argv) < 2:
        log_error(f"Usage: {sys.argv[0]} <instance-id> [log-file]")
        log_error("Default log files:")
        log_error("  - /var/log/user-data.log (user data script execution)")
        log_error("  - /root/runner.log (GitHub Actions Runner logs)")
        log_error("  - /root/setup-runner.log (setup script logs)")
        sys.exit(1)
    
    instance_id = sys.argv[1]
    log_file = sys.argv[2] if len(sys.argv) > 2 else "/var/log/user-data.log"
    
    log_info(f"Fetching logs for instance: {instance_id}")
    log_info(f"Log file: {log_file}")
    
    # Get instance info
    instance_info = get_instance_info(instance_id)
    if not instance_info:
        log_error("Failed to get instance information")
        sys.exit(1)
    
    status = instance_info.get("Status")
    log_info(f"Instance status: {status}")
    
    if status != "Running":
        log_error(f"Instance is not running (status: {status})")
        sys.exit(1)
    
    # Try to get logs
    logs = get_instance_logs_via_ssh(instance_id, log_file)
    
    if logs:
        print("\n" + "="*80)
        print(f"Logs from {log_file}:")
        print("="*80)
        print(logs)
    else:
        log_info("Automatic log retrieval not available")
        log_info("You can:")
        log_info("1. SSH to the instance and check logs manually")
        log_info("2. Check Aliyun Console > ECS > Instance > Cloud Assistant")
        log_info("3. View instance system logs in Aliyun Console")


if __name__ == "__main__":
    main()

