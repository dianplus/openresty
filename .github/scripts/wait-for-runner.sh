#!/bin/bash

# 等待 Runner 上线
# 轮询检查 Runner 是否成功注册到 GitHub

set -euo pipefail

# 从环境变量获取参数
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
RUNNER_NAME="${RUNNER_NAME:-}"
TIMEOUT="${TIMEOUT:-300}"  # 默认超时时间 5 分钟
INTERVAL="${INTERVAL:-10}"  # 默认轮询间隔 10 秒

# 验证必需参数
if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "Error: GITHUB_TOKEN is required" >&2
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  echo "Error: GITHUB_REPOSITORY is required" >&2
  exit 1
fi

if [[ -z "${RUNNER_NAME}" ]]; then
  echo "Error: RUNNER_NAME is required" >&2
  exit 1
fi

echo "Waiting for runner: ${RUNNER_NAME}"
echo "Timeout: ${TIMEOUT} seconds"
echo "Polling interval: ${INTERVAL} seconds"

# 计算最大轮询次数
MAX_ATTEMPTS=$((TIMEOUT / INTERVAL))
ATTEMPT=0

# 轮询检查 Runner 是否上线
while [[ ${ATTEMPT} -lt ${MAX_ATTEMPTS} ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "Checking runner status (attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."

  # 调用 GitHub API 查询 Runner 列表
  # API: GET /repos/{owner}/{repo}/actions/runners
  response=$(curl -s -w "\n%{http_code}" \
    -X GET \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners")

  # 分离响应体和状态码
  http_code=$(echo "${response}" | tail -n1)
  body=$(echo "${response}" | sed '$d')

  if [[ "${http_code}" != "200" ]]; then
    echo "Warning: Failed to query runners (HTTP ${http_code})" >&2
    echo "Response: ${body}" >&2
    sleep ${INTERVAL}
    continue
  fi

  # 检查 Runner 是否在列表中
  if echo "${body}" | jq -e --arg name "${RUNNER_NAME}" '.runners[] | select(.name == $name)' > /dev/null 2>&1; then
    # 获取 Runner 状态
    RUNNER_STATUS=$(echo "${body}" | jq -r --arg name "${RUNNER_NAME}" '.runners[] | select(.name == $name) | .status')
    RUNNER_ID=$(echo "${body}" | jq -r --arg name "${RUNNER_NAME}" '.runners[] | select(.name == $name) | .id')
    
    echo "Runner found: ${RUNNER_NAME}"
    echo "Runner ID: ${RUNNER_ID}"
    echo "Runner Status: ${RUNNER_STATUS}"
    
    # 检查 Runner 是否在线
    if [[ "${RUNNER_STATUS}" == "online" ]]; then
      echo "Runner is online!"
      if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "runner_online=true" >> "${GITHUB_OUTPUT}"
      fi
      exit 0
    else
      echo "Runner is registered but not online yet (status: ${RUNNER_STATUS})"
    fi
  else
    echo "Runner not found yet"
  fi

  # 等待下次轮询
  if [[ ${ATTEMPT} -lt ${MAX_ATTEMPTS} ]]; then
    sleep ${INTERVAL}
  fi
done

# 超时未找到 Runner
echo "Error: Runner did not come online within ${TIMEOUT} seconds" >&2
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "runner_online=false" >> "${GITHUB_OUTPUT}"
fi
exit 1

