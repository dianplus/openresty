#!/bin/bash

# 获取 GitHub Actions Runner Registration Token
# 使用 GitHub API 获取临时注册令牌

set -euo pipefail

# 从环境变量获取参数
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "Error: GITHUB_TOKEN is required" >&2
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  echo "Error: GITHUB_REPOSITORY is required" >&2
  exit 1
fi

# 调用 GitHub API 获取 registration token
# API: POST /repos/{owner}/{repo}/actions/runners/registration-token
response=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token")

# 分离响应体和状态码
http_code=$(echo "${response}" | tail -n1)
body=$(echo "${response}" | sed '$d')

if [[ "${http_code}" != "201" ]]; then
  echo "Error: Failed to get registration token (HTTP ${http_code})" >&2
  echo "Response: ${body}" >&2
  exit 1
fi

# 提取 token
token=$(echo "${body}" | jq -r '.token')

if [[ -z "${token}" || "${token}" == "null" ]]; then
  echo "Error: Failed to extract token from response" >&2
  echo "Response: ${body}" >&2
  exit 1
fi

# 输出 token（用于 GitHub Actions 捕获）
echo "${token}"

