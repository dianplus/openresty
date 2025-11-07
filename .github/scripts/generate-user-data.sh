#!/bin/bash

# 从模板生成 User Data 脚本
# 将模板中的变量替换为实际值

set -euo pipefail

# 从环境变量获取参数
TEMPLATE_FILE="${TEMPLATE_FILE:-.github/templates/user-data.sh}"
RUNNER_REGISTRATION_TOKEN="${RUNNER_REGISTRATION_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
RUNNER_NAME="${RUNNER_NAME:-}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_VERSION="${RUNNER_VERSION:-}"
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-}"
ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME="${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME:-}"

# 验证必需参数
if [[ -z "${RUNNER_REGISTRATION_TOKEN}" ]]; then
  echo "Error: RUNNER_REGISTRATION_TOKEN is required" >&2
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

# 检查模板文件是否存在
if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "Error: Template file not found: ${TEMPLATE_FILE}" >&2
  exit 1
fi

# 读取模板文件
USER_DATA=$(cat "${TEMPLATE_FILE}")

# 替换变量（使用更安全的 sed 替换，转义特殊字符）
# 转义特殊字符
RUNNER_REGISTRATION_TOKEN_ESC=$(echo "${RUNNER_REGISTRATION_TOKEN}" | sed 's/[[\.*^$()+?{|]/\\&/g')
GITHUB_REPOSITORY_ESC=$(echo "${GITHUB_REPOSITORY}" | sed 's/[[\.*^$()+?{|]/\\&/g')
RUNNER_NAME_ESC=$(echo "${RUNNER_NAME}" | sed 's/[[\.*^$()+?{|]/\\&/g')

# 替换必需变量
USER_DATA=$(echo "${USER_DATA}" | sed "s|RUNNER_REGISTRATION_TOKEN=\"\${RUNNER_REGISTRATION_TOKEN:-}\"|RUNNER_REGISTRATION_TOKEN=\"${RUNNER_REGISTRATION_TOKEN_ESC}\"|")
USER_DATA=$(echo "${USER_DATA}" | sed "s|GITHUB_REPOSITORY=\"\${GITHUB_REPOSITORY:-}\"|GITHUB_REPOSITORY=\"${GITHUB_REPOSITORY_ESC}\"|")
USER_DATA=$(echo "${USER_DATA}" | sed "s|RUNNER_NAME=\"\${RUNNER_NAME:-}\"|RUNNER_NAME=\"${RUNNER_NAME_ESC}\"|")

# 替换可选变量
if [[ -n "${RUNNER_LABELS}" ]]; then
  RUNNER_LABELS_ESC=$(echo "${RUNNER_LABELS}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|RUNNER_LABELS=\"\${RUNNER_LABELS:-}\"|RUNNER_LABELS=\"${RUNNER_LABELS_ESC}\"|")
fi

if [[ -n "${RUNNER_VERSION}" ]]; then
  RUNNER_VERSION_ESC=$(echo "${RUNNER_VERSION}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|RUNNER_VERSION=\"\${RUNNER_VERSION:-2.311.0}\"|RUNNER_VERSION=\"${RUNNER_VERSION_ESC}\"|")
fi

if [[ -n "${HTTP_PROXY}" ]]; then
  HTTP_PROXY_ESC=$(echo "${HTTP_PROXY}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|HTTP_PROXY=\"\${HTTP_PROXY:-}\"|HTTP_PROXY=\"${HTTP_PROXY_ESC}\"|")
fi

if [[ -n "${HTTPS_PROXY}" ]]; then
  HTTPS_PROXY_ESC=$(echo "${HTTPS_PROXY}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|HTTPS_PROXY=\"\${HTTPS_PROXY:-}\"|HTTPS_PROXY=\"${HTTPS_PROXY_ESC}\"|")
fi

if [[ -n "${NO_PROXY}" ]]; then
  NO_PROXY_ESC=$(echo "${NO_PROXY}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|NO_PROXY=\"\${NO_PROXY:-.*}\"|NO_PROXY=\"${NO_PROXY_ESC}\"|")
fi

if [[ -n "${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}" ]]; then
  ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME_ESC=$(echo "${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}" | sed 's/[[\.*^$()+?{|]/\\&/g')
  USER_DATA=$(echo "${USER_DATA}" | sed "s|ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME=\"\${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME:-}\"|ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME=\"${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME_ESC}\"|")
fi

# 输出生成的 User Data
echo "${USER_DATA}"

