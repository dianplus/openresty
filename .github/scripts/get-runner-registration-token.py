#!/usr/bin/env python3
"""
Get GitHub Actions runner registration token.

This script fetches a registration token from GitHub API, which is required
to register a self-hosted runner. The token is temporary (typically 1 hour).

Usage: ./get-runner-registration-token.py <github-token> <repo-owner> <repo-name>
"""

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Optional


def log_info(msg: str) -> None:
    """Print info message."""
    print(f"ℹ️  {msg}")


def log_error(msg: str) -> None:
    """Print error message."""
    print(f"❌ {msg}")


def get_registration_token(github_token: str, owner: str, repo: str) -> Optional[str]:
    """Get runner registration token from GitHub API."""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token"
    headers = {
        "Authorization": f"token {github_token}",
        "Accept": "application/vnd.github.v3+json",
    }
    
    try:
        req = urllib.request.Request(url, headers=headers, method="POST")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read())
            token = data.get("token")
            if token:
                log_info("Successfully obtained registration token")
                return token
            else:
                log_error("Registration token not found in API response")
                return None
    except urllib.error.HTTPError as e:
        if e.code == 403:
            log_error("Permission denied: GitHub token lacks required permissions")
            log_error("Required permissions: repo scope or admin:repo scope")
            log_error(f"API response: {e.read().decode()}")
        elif e.code == 404:
            log_error(f"Repository not found: {owner}/{repo}")
        else:
            log_error(f"HTTP error {e.code}: {e.reason}")
        return None
    except Exception as e:
        log_error(f"Failed to get registration token: {e}")
        return None


def main():
    """Main function."""
    if len(sys.argv) < 4:
        log_error(f"Usage: {sys.argv[0]} <github-token> <repo-owner> <repo-name>")
        log_error("Example: ./get-runner-registration-token.py <token> dianplus openresty")
        sys.exit(1)
    
    github_token = sys.argv[1]
    owner = sys.argv[2]
    repo = sys.argv[3]
    
    log_info(f"Fetching registration token for {owner}/{repo}...")
    
    token = get_registration_token(github_token, owner, repo)
    
    if token:
        print(token)
        sys.exit(0)
    else:
        log_error("Failed to get registration token")
        sys.exit(1)


if __name__ == "__main__":
    main()

