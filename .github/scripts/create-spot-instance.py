#!/usr/bin/env python3
"""
Create a spot ECS instance with GitHub Actions Runner.

Usage: ./create-spot-instance.py <instance-type> <zone> <spot-price-limit> <image-id> <security-group-id> <vswitch-id> <key-pair-name> <github-token> <runner-name> <architecture>
Outputs: instance_id (via GitHub Actions outputs)
"""

import base64
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


def generate_user_data(github_token: str, runner_name: str, architecture: str) -> str:
    """Generate user data script for ECS instance."""
    # Architecture label mapping
    arch_label = "ARM64" if architecture == "arm64" else "X64"
    
    user_data_template = f"""#!/bin/bash
set -e

# Export environment variables needed by setup-runner.sh
export GITHUB_TOKEN="{github_token}"
export RUNNER_NAME="{runner_name}-$(date +%s)"

# Set proxy variables if available (from ECS instance metadata or defaults)
# These will be properly configured by setup-runner.sh if needed
[ -n "${{HTTP_PROXY:-}}" ] && export HTTP_PROXY="${{HTTP_PROXY}}"
[ -n "${{HTTPS_PROXY:-}}" ] && export HTTPS_PROXY="${{HTTPS_PROXY}}"
[ -n "${{NO_PROXY:-}}" ] && export NO_PROXY="${{NO_PROXY}}"

# Download and execute the setup script
# Use HTTP_PROXY if set, otherwise proceed without proxy
if [ -n "${{HTTP_PROXY:-}}" ]; then
  curl -s --proxy "${{HTTP_PROXY}}" https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/setup-runner.sh -o setup-runner.sh
else
  curl -s https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/setup-runner.sh -o setup-runner.sh
fi

chmod +x setup-runner.sh

# Execute the setup script
./setup-runner.sh {architecture}
"""
    return user_data_template


def create_instance(
    instance_type: str,
    zone: str,
    spot_price_limit: str,
    image_id: str,
    security_group_id: str,
    vswitch_id: str,
    key_pair_name: str,
    user_data: str,
) -> Optional[str]:
    """Create ECS spot instance and return instance ID."""
    # Encode user data to base64
    user_data_b64 = base64.b64encode(user_data.encode()).decode()
    
    # Build aliyun CLI command
    # Note: aliyun CLI doesn't support --output as a global option
    # We'll parse the default table format or use output redirection
    cmd = [
        "aliyun",
        "ecs",
        "RunInstances",
        "--ImageId", image_id,
        "--InstanceType", instance_type,
        "--SecurityGroupId", security_group_id,
        "--VSwitchId", vswitch_id,
        "--ZoneId", zone,
        "--SpotStrategy", "SpotWithPriceLimit",
        "--SpotPriceLimit", spot_price_limit,
        "--SystemDisk.Category", "cloud_essd",
        "--SystemDisk.Size", "40",
        "--KeyPairName", key_pair_name,
        "--UserData", user_data_b64,
    ]
    
    log_info("Creating ECS instance...")
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        
        # aliyun CLI default output format
        # Try to parse JSON first, then fallback to other formats
        response_text = result.stdout.strip()
        
        # Try parsing as JSON
        response = None
        if response_text.startswith("{") or response_text.startswith("["):
            try:
                response = json.loads(response_text)
            except json.JSONDecodeError as e:
                log_error(f"Failed to parse JSON: {e}")
                log_error(f"Response: {response_text[:500]}")
                return None
        
        if response:
            # Extract instance ID from JSON response
            instance_id = response.get("InstanceIdSets", {}).get("InstanceIdSet", [])
            if instance_id:
                return instance_id[0]
            else:
                log_error("No instance ID in JSON response")
                log_error(f"Response structure: {json.dumps(response, indent=2)[:500]}")
                return None
        else:
            # Try to extract instance ID using regex (for table format or other formats)
            import re
            # Instance ID pattern: i- followed by 17 alphanumeric characters
            instance_id_match = re.search(r'(i-[a-z0-9]{17})', response_text)
            if instance_id_match:
                return instance_id_match.group(1)
            else:
                log_error(f"Could not parse response format. Response: {response_text[:500]}")
                return None
            
    except subprocess.CalledProcessError as e:
        log_error(f"Failed to create instance: {e}")
        log_error(f"Error output: {e.stderr}")
        log_error(f"Standard output: {e.stdout[:500] if e.stdout else 'None'}")
        return None
    except Exception as e:
        log_error(f"Unexpected error: {e}")
        log_error(f"Response: {result.stdout[:500] if 'result' in locals() else 'N/A'}")
        return None


def get_vswitch_id_for_zone(zone: str) -> Optional[str]:
    """Get VSwitch ID for the given zone.
    
    Zone format: cn-hangzhou-{zone_suffix} (e.g., cn-hangzhou-j)
    Must use ALIYUN_VSWITCH_ID_{ZONE_SUFFIX} - no fallback to avoid creating
    instances in wrong VSwitch which may cause network/price issues.
    """
    # Extract zone suffix (e.g., 'j' from 'cn-hangzhou-j')
    zone_suffix = zone.split("-")[-1].upper() if "-" in zone else ""
    
    if not zone_suffix:
        log_error(f"Invalid zone format: {zone}. Expected format: cn-hangzhou-{{suffix}}")
        return None
    
    # Get zone-specific vswitch ID (required, no fallback)
    zone_vswitch_key = f"ALIYUN_VSWITCH_ID_{zone_suffix}"
    zone_vswitch_id = os.environ.get(zone_vswitch_key)
    
    if zone_vswitch_id:
        log_info(f"Using zone-specific VSwitch ID from {zone_vswitch_key}")
        return zone_vswitch_id
    
    log_error(f"VSwitch ID not found for zone {zone} (expected {zone_vswitch_key})")
    log_error("Zone-specific VSwitch ID is required to ensure instance is created in correct network")
    log_error("Please configure the corresponding secret in GitHub repository settings")
    return None


def main():
    """Main function."""
    if len(sys.argv) < 11:
        log_error(f"Usage: {sys.argv[0]} <instance-type> <zone> <spot-price-limit> <image-id> <security-group-id> <unused-vswitch-param> <key-pair-name> <github-token> <runner-name> <architecture>")
        log_error("Note: VSwitch ID is now auto-selected based on zone. The vswitch parameter is kept for compatibility but not used.")
        sys.exit(1)
    
    instance_type = sys.argv[1]
    zone = sys.argv[2]
    spot_price_limit = sys.argv[3]
    image_id = sys.argv[4]
    security_group_id = sys.argv[5]
    # vswitch_id parameter kept for compatibility but not used - we auto-select based on zone
    key_pair_name = sys.argv[7]
    github_token = sys.argv[8]
    runner_name = sys.argv[9]
    architecture = sys.argv[10]
    
    log_info("Creating spot instance...")
    log_info(f"Instance type: {instance_type}")
    log_info(f"Zone: {zone}")
    log_info(f"Spot price limit: {spot_price_limit}")
    log_info(f"Architecture: {architecture}")
    
    # Get VSwitch ID based on zone (must be zone-specific, no fallback)
    vswitch_id = get_vswitch_id_for_zone(zone)
    if not vswitch_id:
        log_error(f"Cannot create instance in zone {zone} without zone-specific VSwitch ID")
        log_error("This ensures instances are created in the correct network for their availability zone")
        sys.exit(1)
    
    log_info(f"Selected VSwitch ID: {vswitch_id[:20]}...")
    
    # Validate required parameters
    if not image_id:
        log_error("Image ID is required but not provided")
        sys.exit(1)
    if not security_group_id:
        log_error("Security Group ID is required but not provided")
        sys.exit(1)
    if not key_pair_name:
        log_error("Key Pair Name is required but not provided")
        sys.exit(1)
    
    # Generate user data
    log_info("Generating user data script...")
    user_data = generate_user_data(github_token, runner_name, architecture)
    
    # Create instance
    instance_id = create_instance(
        instance_type=instance_type,
        zone=zone,
        spot_price_limit=spot_price_limit,
        image_id=image_id,
        security_group_id=security_group_id,
        vswitch_id=vswitch_id,  # Use zone-specific vswitch ID
        key_pair_name=key_pair_name,
        user_data=user_data,
    )
    
    if not instance_id or instance_id == "null":
        log_error("Failed to create instance")
        sys.exit(1)
    
    # Output to GitHub Actions
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"instance_id={instance_id}\n")
    
    log_success(f"Created instance: {instance_id}")


if __name__ == "__main__":
    main()

