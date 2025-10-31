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
    """Print info message to stderr."""
    print(f"ℹ️  {msg}", file=sys.stderr)


def log_error(msg: str) -> None:
    """Print error message to stderr."""
    print(f"❌ {msg}", file=sys.stderr)


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
        error_body = ""
        try:
            error_body = e.read().decode()
        except:
            pass
        
        if e.code == 403:
            log_error("Permission denied: GitHub token lacks required permissions")
            log_error("Required permissions: actions:write (for GITHUB_TOKEN) or repo scope")
            if error_body:
                log_error(f"API response: {error_body}")
        elif e.code == 404:
            log_error(f"Repository not found: {owner}/{repo}")
            if error_body:
                log_error(f"API response: {error_body}")
        else:
            log_error(f"HTTP error {e.code}: {e.reason}")
            if error_body:
                log_error(f"API response: {error_body}")
        return None
    except Exception as e:
        log_error(f"Failed to get registration token: {e}")
        import traceback
        log_error(f"Traceback: {traceback.format_exc()}")
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
        # Output token to stdout only (for capturing in shell variable)
        print(token, file=sys.stdout)
        sys.exit(0)
    else:
        log_error("Failed to get registration token")
        log_error("Please check:")
        log_error("1. GitHub token has 'actions:write' permission")
        log_error("2. Repository name and owner are correct")
        log_error("3. Network connectivity to api.github.com")
        sys.exit(1)


if __name__ == "__main__":
    main()

