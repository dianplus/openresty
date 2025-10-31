#!/usr/bin/env python3
"""
Check runner setup status and logs from ECS instance.

Usage: ./check-runner-status.py <instance-id>

This script checks:
1. Instance status
2. Runner process status (via Cloud Assistant or suggests SSH)
3. Runner registration status on GitHub
4. Log files location
"""

import json
import os
import subprocess
import sys
from typing import Optional, Dict, Any


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


def get_instance_info(instance_id: str) -> Optional[Dict[str, Any]]:
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


def check_runner_on_github(runner_name_pattern: str) -> Optional[Dict[str, Any]]:
    """Check if runner is registered on GitHub."""
    github_token = os.environ.get("GITHUB_TOKEN")
    if not github_token:
        log_warning("GITHUB_TOKEN not set, cannot check GitHub runner status")
        return None
    
    import urllib.request
    import urllib.error
    
    url = "https://api.github.com/repos/dianplus/openresty/actions/runners"
    headers = {
        "Authorization": f"token {github_token}",
        "Accept": "application/vnd.github.v3+json",
    }
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read())
            runners = data.get("runners", [])
            
            # Find matching runner
            for runner in runners:
                if runner_name_pattern in runner.get("name", ""):
                    return runner
    except Exception as e:
        log_warning(f"Failed to check GitHub runner status: {e}")
    
    return None


def main():
    """Main function."""
    if len(sys.argv) < 2:
        log_error(f"Usage: {sys.argv[0]} <instance-id>")
        sys.exit(1)
    
    instance_id = sys.argv[1]
    
    log_info(f"Checking runner status for instance: {instance_id}")
    print()
    
    # Get instance info
    instance_info = get_instance_info(instance_id)
    if not instance_info:
        log_error("Failed to get instance information")
        sys.exit(1)
    
    # Display instance info
    status = instance_info.get("Status")
    instance_name = instance_info.get("InstanceName", "N/A")
    zone = instance_info.get("ZoneId", "N/A")
    instance_type = instance_info.get("InstanceType", "N/A")
    
    print("=" * 80)
    print("Instance Information:")
    print("=" * 80)
    print(f"  Instance ID: {instance_id}")
    print(f"  Instance Name: {instance_name}")
    print(f"  Status: {status}")
    print(f"  Zone: {zone}")
    print(f"  Instance Type: {instance_type}")
    
    public_ip = instance_info.get("PublicIpAddress", {}).get("IpAddress", [])
    if public_ip:
        ip = public_ip[0] if isinstance(public_ip, list) else public_ip
        print(f"  Public IP: {ip}")
    else:
        print(f"  Public IP: Not available")
    
    print()
    
    # Check GitHub runner status
    if instance_name:
        print("=" * 80)
        print("GitHub Runner Status:")
        print("=" * 80)
        runner_info = check_runner_on_github(instance_name)
        if runner_info:
            runner_status = runner_info.get("status", "unknown")
            runner_busy = runner_info.get("busy", False)
            runner_name = runner_info.get("name", "N/A")
            print(f"  Runner Name: {runner_name}")
            print(f"  Status: {runner_status}")
            print(f"  Busy: {runner_busy}")
            
            if runner_status == "online":
                log_success("Runner is online and registered")
            elif runner_status == "offline":
                log_warning("Runner is registered but offline")
            else:
                log_warning(f"Runner status: {runner_status}")
        else:
            log_warning("Runner not found on GitHub (may still be setting up)")
        print()
    
    # Log locations
    print("=" * 80)
    print("Log Files Location:")
    print("=" * 80)
    print("Cloud-init Logs:")
    print("  - /var/log/cloud-init.log")
    print("  - /var/log/cloud-init-output.log")
    print("  - /var/lib/cloud/instances/*/user-data.txt")
    print()
    print("Application Logs:")
    print("  - User Data Script: /var/log/user-data.log")
    print("  - Setup Script: /var/log/github-runner/setup.log")
    print("  - Runner Logs: /var/log/github-runner/runner.log")
    print("  - Runner PID: /var/log/github-runner/runner.pid")
    print()
    
    # Instructions
    print("=" * 80)
    print("How to View Logs:")
    print("=" * 80)
    if public_ip:
        ip = public_ip[0] if isinstance(public_ip, list) else public_ip
        print("1. SSH to the instance:")
        print(f"   ssh root@{ip}")
        print()
        print("2. Check cloud-init status:")
        print("   cloud-init status")
        print()
        print("3. View logs:")
        print("   tail -f /var/log/cloud-init.log")
        print("   tail -f /var/log/cloud-init-output.log")
        print("   tail -f /var/log/user-data.log")
        print("   tail -f /var/log/github-runner/setup.log")
        print("   tail -f /var/log/github-runner/runner.log")
        print()
        print("4. Check runner process:")
        print("   ps aux | grep runner")
        print("   cat /var/log/github-runner/runner.pid")
    else:
        print("1. Instance has no public IP, use Aliyun Console:")
        print("   - Go to ECS > Instances > Select instance")
        print("   - Use Cloud Assistant to execute commands")
        print("   - Or configure VPC connection for SSH access")
    print()
    print("4. Alternative: Use Aliyun Cloud Assistant (if configured)")
    print("   aliyun ecs InvokeCommand --InstanceId <instance-id> --CommandContent 'cat /var/log/user-data.log'")


if __name__ == "__main__":
    main()

