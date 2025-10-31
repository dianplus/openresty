#!/usr/bin/env python3
"""
Find the cheapest spot instance in a given region.

Usage: ./find-cheapest-instance.py <region> <instance-types> <min-cpu> <max-cpu> <min-memory> <max-memory>
Outputs: cheapest_instance, cheapest_zone, spot_price_limit (via GitHub Actions outputs)
"""

import json
import os
import subprocess
import sys
import tempfile
import platform
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from urllib.request import urlopen
import shutil


def log_info(msg: str) -> None:
    """Print info message."""
    print(f"ℹ️  {msg}")


def log_success(msg: str) -> None:
    """Print success message."""
    print(f"✅ {msg}")


def log_error(msg: str) -> None:
    """Print error message."""
    print(f"❌ {msg}")


def get_spot_instance_advisor_path() -> Optional[str]:
    """Get spot-instance-advisor command path."""
    # Check if already in PATH
    if shutil.which("spot-instance-advisor"):
        return "spot-instance-advisor"
    
    # Check common installation paths
    common_paths = [
        "/usr/local/bin/spot-instance-advisor",
        os.path.expanduser("~/.local/bin/spot-instance-advisor"),
    ]
    
    for path in common_paths:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    
    return None


def download_spot_instance_advisor() -> str:
    """Download and install spot-instance-advisor from GitHub releases."""
    log_info("Downloading spot-instance-advisor from GitHub maskshell releases...")
    
    # Detect OS and architecture
    os_name = platform.system().lower()
    arch = platform.machine().lower()
    
    # Normalize architecture
    if arch in ("x86_64", "amd64"):
        arch = "amd64"
    elif arch in ("aarch64", "arm64"):
        arch = "arm64"
    else:
        log_error(f"Unsupported architecture: {arch}")
        sys.exit(1)
    
    # Normalize OS
    if os_name == "darwin":
        os_name = "darwin"
    elif os_name == "linux":
        os_name = "linux"
    else:
        log_error(f"Unsupported OS: {os_name}")
        sys.exit(1)
    
    log_info(f"Detected OS: {os_name}, Architecture: {arch}")
    
    # Get latest release from GitHub API
    repo = "maskshell/spot-instance-advisor"
    api_url = f"https://api.github.com/repos/{repo}/releases/latest"
    
    log_info(f"Fetching latest release info from {api_url}")
    
    try:
        with urlopen(api_url) as response:
            release_info = json.loads(response.read())
    except Exception as e:
        log_error(f"Failed to fetch release info from GitHub API: {e}")
        sys.exit(1)
    
    tag_name = release_info.get("tag_name")
    if not tag_name:
        log_error("Failed to parse release tag from GitHub API")
        sys.exit(1)
    
    log_info(f"Latest release: {tag_name}")
    
    # Find matching binary in release assets
    assets = release_info.get("assets", [])
    download_url = None
    binary_name = None
    
    # Try to match: spot-instance-advisor-<os>-<arch>
    pattern = f"{os_name}-{arch}"
    authors = None
    for asset in assets:
        browser_url = asset.get("browser_download_url", "")
        if pattern in browser_url:
            download_url = browser_url
            binary_name = asset.get("name", "")
            break
    
    # Try alternative pattern: just <arch>
    if not download_url:
        for asset in assets:
            browser_url = asset.get("browser_download_url", "")
            if arch in browser_url.lower() and "spot-instance-advisor" in browser_url.lower():
                download_url = browser_url
                binary_name = asset.get("name", "")
                break
    
    # Fallback: use first asset
    if not download_url and assets:
        download_url = assets[0].get("browser_download_url")
        binary_name = assets[0].get("name", "")
        log_info(f"Using first available asset: {binary_name}")
    
    if not download_url:
        log_error("No matching binary found in release assets")
        sys.exit(1)
    
    log_info(f"Downloading from: {download_url}")
    
    # Download binary
    with tempfile.TemporaryDirectory() as temp_dir:
        downloaded_file = os.path.join(temp_dir, binary_name)
        
        try:
            with urlopen(download_url) as response:
                with open(downloaded_file, "wb") as f:
                    f.write(response.read())
        except Exception as e:
            log_error(f"Failed to download spot-instance-advisor: {e}")
            sys.exit(1)
        
        # Extract if archive
        binary_path = None
        if binary_name.endswith((".tar.gz", ".tgz")):
            log_info("Extracting archive...")
            import tarfile
            with tarfile.open(downloaded_file, "r:gz") as tar:
                tar.extractall(temp_dir)
            # Find extracted binary
            for root, dirs, files in os.walk(temp_dir):
                if "spot-instance-advisor" in files:
                    binary_path = os.path.join(root, "spot-instance-advisor")
                    break
        elif binary_name.endswith(".zip"):
            log_info("Extracting archive...")
            import zipfile
            with zipfile.ZipFile(downloaded_file, "r") as zip_ref:
                zip_ref.extractall(temp_dir)
            # Find extracted binary
            for root, dirs, files in os.walk(temp_dir):
                if "spot-instance-advisor" in files:
                    binary_path = os.path.join(root, "spot-instance-advisor")
                    break
        else:
            binary_path = downloaded_file
        
        if not binary_path or not os.path.isfile(binary_path):
            log_error("Failed to find binary in archive")
            sys.exit(1)
        
        # Make executable
        os.chmod(binary_path, 0o755)
        
        # Install to appropriate directory
        if os.access("/usr/local/bin", os.W_OK):
            install_dir = "/usr/local/bin"
        else:
            install_dir = os.path.expanduser("~/.local/bin")
            os.makedirs(install_dir, exist_ok=True)
            # Add to PATH for current session
            os.environ["PATH"] = f"{install_dir}:{os.environ.get('PATH', '')}"
        
        install_path = os.path.join(install_dir, "spot-instance-advisor")
        shutil.move(binary_path, install_path)
        
        log_success(f"spot-instance-advisor installed to {install_dir}")
        
        return install_path


def get_aliyun_credentials() -> Tuple[str, str]:
    """Get Aliyun credentials from environment or config file."""
    # Try environment variables first
    access_key_id = os.environ.get("ALIYUN_ACCESS_KEY_ID")
    access_key_secret = os.environ.get("ALIYUN_ACCESS_KEY_SECRET")
    
    if access_key_id and access_key_secret:
        log_info("Using credentials from environment variables")
        return access_key_id, access_key_secret
    
    # Try reading from aliyun CLI config
    config_path = Path.home() / ".aliyun" / "config.json"
    if config_path.exists():
        log_info("Reading credentials from aliyun CLI config file")
        try:
            with open(config_path) as f:
                config = json.load(f)
            
            # Try different config structures
            profiles = config.get("profiles", [])
            if profiles and isinstance(profiles, list):
                profile = profiles[0]
                mode_ak = profile.get("mode_ak", {})
                access_key_id = mode_ak.get("access_key_id")
                access_key_secret = mode_ak.get("access_key_secret")
            
            if access_key_id and access_key_secret:
                return access_key_id, access_key_secret
        except Exception as e:
            log_error(f"Failed to read aliyun config: {e}")
    
    log_error("Aliyun credentials not found. Please set ALIYUN_ACCESS_KEY_ID and ALIYUN_ACCESS_KEY_SECRET environment variables or configure aliyun CLI.")
    sys.exit(1)


def normalize_field(data: Dict[str, Any], *field_names: str) -> Optional[Any]:
    """Try multiple field name variations (case-insensitive)."""
    for field_name in field_names:
        # Try exact match
        if field_name in data:
            return data[field_name]
        # Try case-insensitive match
        for key in data.keys():
            if key.lower() == field_name.lower():
                return data[key]
    return None


def parse_spot_prices(json_data: Any, instance_type_prefix: str = "ecs.c8y") -> List[Dict[str, Any]]:
    """Parse spot prices from JSON response."""
    prices = []
    
    # Handle different JSON structures
    if isinstance(json_data, list):
        # Direct array format
        log_info("Detected JSON format: array")
        prices = json_data
        # Debug: print first item structure if available
        if prices and isinstance(prices[0], dict):
            log_info(f"Sample item keys: {list(prices[0].keys())[:10]}")
    elif isinstance(json_data, dict):
        # Object format
        log_info("Detected JSON format: object")
        # Try .spot_prices
        if "spot_prices" in json_data:
            prices = json_data["spot_prices"]
        else:
            # Find first array field
            for key, value in json_data.items():
                if isinstance(value, list):
                    prices = value
                    log_info(f"Using array field: {key}")
                    break
    
    if not prices:
        log_error("No price data found in JSON response")
        return []
    
    log_info(f"Found {len(prices)} price entries")
    
    # Normalize and filter prices
    normalized_prices = []
    skipped_count = 0
    
    for price in prices:
        if not isinstance(price, dict):
            skipped_count += 1
            continue
        
        # Try multiple field name variations
        # Common patterns: instanceTypeId, instance_type, InstanceType, etc.
        instance_type = normalize_field(
            price,
            "instanceTypeId", "instance_type", "InstanceType", "instanceType",
            "Instance", "Type", "instance", "type"
        )
        zone = normalize_field(
            price,
            "zoneId", "zone", "Zone", "availability_zone", "AvailabilityZone",
            "az", "AZ", "ZoneId"
        )
        price_per_core = normalize_field(
            price,
            "pricePerCore", "price_per_core", "PricePerCore", "pricePerCore",
            "Price", "price", "spot_price", "SpotPrice",
            "per_core_price"
        )
        
        # Debug first item if fields not found
        if not instance_type and normalized_prices == [] and skipped_count == 0:
            log_info(f"Debug: First item structure: {json.dumps(price, indent=2)[:500]}")
        
        if not instance_type:
            skipped_count += 1
            continue
        
        if not price_per_core:
            skipped_count += 1
            continue
        
        # Filter by instance type prefix
        if instance_type_prefix and not instance_type.startswith(instance_type_prefix):
            skipped_count += 1
            continue
        
        normalized_prices.append({
            "instance_type": instance_type,
            "zone": zone or "",
            "price_per_core": float(price_per_core),
        })
    
    if skipped_count > 0:
        log_info(f"Skipped {skipped_count} entries (missing fields or wrong type)")
    
    log_info(f"Filtered to {len(normalized_prices)} matching instances")
    
    return normalized_prices


def get_cpu_cores(instance_type: str) -> int:
    """Extract CPU cores from instance type name."""
    if instance_type.endswith(".8xlarge"):
        return 32
    elif instance_type.endswith(".4xlarge"):
        return 16
    elif instance_type.endswith(".2xlarge"):
        return 8
    elif instance_type.endswith(".xlarge"):
        return 4
    elif instance_type.endswith(".large"):
        return 2
    else:
        return 8  # default


def main():
    """Main function."""
    if len(sys.argv) < 7:
        log_error(f"Usage: {sys.argv[0]} <region> <instance-types> <min-cpu> <max-cpu> <min-memory> <max-memory>")
        sys.exit(1)
    
    region = sys.argv[1]
    instance_types = sys.argv[2]
    min_cpu = sys.argv[3]
    max_cpu = sys.argv[4]
    min_memory = sys.argv[5]
    max_memory = sys.argv[6]
    
    log_info(f"Querying spot instance prices in region: {region}")
    log_info(f"Instance types: {instance_types}")
    log_info(f"CPU range: {min_cpu} - {max_cpu}")
    log_info(f"Memory range: {min_memory} - {max_memory}")
    
    # Ensure spot-instance-advisor is installed
    advisor_cmd = get_spot_instance_advisor_path()
    if not advisor_cmd:
        advisor_cmd = download_spot_instance_advisor()
    
    log_success("spot-instance-advisor is ready to use")
    
    # Get credentials
    access_key_id, access_key_secret = get_aliyun_credentials()
    
    # Build command
    cmd = [
        advisor_cmd,
        f"-accessKeyId={access_key_id}",
        f"-accessKeySecret={access_key_secret}",
        f"-region={region}",
        f"-mincpu={min_cpu}",
        f"-maxcpu={max_cpu}",
        f"-minmem={min_memory}",
        f"-maxmem={max_memory}",
        "-resolution=7",
        "-limit=20",
        "--json",
    ]
    
    if instance_types:
        cmd.append(f"-family={instance_types}")
    
    log_info("Running spot-instance-advisor with parameters...")
    
    # Run command
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        json_data = json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        log_error(f"spot-instance-advisor failed: {e}")
        log_error(f"Error output: {e.stderr}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        log_error(f"Failed to parse JSON response: {e}")
        log_error(f"Response: {result.stdout[:1000]}")
        sys.exit(1)
    
    # Debug: print JSON structure if DEBUG env var is set
    if os.environ.get("DEBUG"):
        log_info("JSON response preview:")
        print(json.dumps(json_data, indent=2)[:1000])
        print("...")
    
    # Parse prices
    # Extract instance type prefix from instance_types parameter if provided
    instance_type_prefix = ""
    if instance_types:
        # Get first instance type family (e.g., "ecs.c8y" from "ecs.c8y.8xlarge,ecs.c8y.4xlarge")
        first_type = instance_types.split(",")[0].strip()
        # Extract family prefix (e.g., "ecs.c8y" from "ecs.c8y.8xlarge")
        parts = first_type.split(".")
        if len(parts) >= 2:
            instance_type_prefix = ".".join(parts[:2])  # e.g., "ecs.c8y"
        else:
            instance_type_prefix = parts[0] if parts else ""
    
    prices = parse_spot_prices(json_data, instance_type_prefix)
    
    if not prices:
        log_error("No suitable instance found")
        if os.environ.get("DEBUG"):
            log_error("Full JSON response:")
            print(json.dumps(json_data, indent=2))
        sys.exit(1)
    
    # Find cheapest
    cheapest = min(prices, key=lambda x: x["price_per_core"])
    
    log_info(f"Cheapest instance: {cheapest['instance_type']}")
    log_info(f"Cheapest zone: {cheapest['zone']}")
    log_info(f"Price per core: {cheapest['price_per_core']}")
    
    # Calculate total price
    cpu_cores = get_cpu_cores(cheapest["instance_type"])
    spot_price_limit = cheapest["price_per_core"] * cpu_cores * 1.2
    
    log_info(f"CPU cores: {cpu_cores}")
    log_info(f"Spot price limit: {spot_price_limit}")
    
    # Output to GitHub Actions
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"cheapest_instance={cheapest['instance_type']}\n")
            f.write(f"cheapest_zone={cheapest['zone']}\n")
            f.write(f"spot_price_limit={spot_price_limit}\n")
    
    log_success("Found cheapest instance configuration")


if __name__ == "__main__":
    main()

