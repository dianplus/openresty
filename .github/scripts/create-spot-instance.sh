#!/bin/bash

# 创建阿里云 ECS Spot 实例
# 用于创建 Self-hosted Runner 实例

set -euo pipefail

# 从环境变量获取参数
ALIYUN_ACCESS_KEY_ID="${ALIYUN_ACCESS_KEY_ID:-}"
ALIYUN_ACCESS_KEY_SECRET="${ALIYUN_ACCESS_KEY_SECRET:-}"
ALIYUN_REGION_ID="${ALIYUN_REGION_ID:-}"
ALIYUN_VPC_ID="${ALIYUN_VPC_ID:-}"
ALIYUN_SECURITY_GROUP_ID="${ALIYUN_SECURITY_GROUP_ID:-}"
ALIYUN_IMAGE_ID="${ALIYUN_IMAGE_ID:-}"
ALIYUN_VSWITCH_ID="${ALIYUN_VSWITCH_ID:-}"
ALIYUN_KEY_PAIR_NAME="${ALIYUN_KEY_PAIR_NAME:-}"
INSTANCE_TYPE="${INSTANCE_TYPE:-}"
INSTANCE_NAME="${INSTANCE_NAME:-}"
USER_DATA="${USER_DATA:-}"
USER_DATA_FILE="${USER_DATA_FILE:-}"
ARCH="${ARCH:-amd64}"  # amd64 或 arm64

# 根据架构设置默认实例类型（如果未指定）
# AMD64: CPU:RAM = 1:1，最小 8c8g（8 核 8GB）
# ARM64: CPU:RAM = 1:2，最小 8c16g（8 核 16GB），限制为 ecs.c8y,ecs.c8r 实例族
if [[ -z "${INSTANCE_TYPE}" ]]; then
  if [[ "${ARCH}" == "amd64" ]]; then
    # AMD64 默认实例类型：需要 8c8g（8 核 8GB）规格
    # 注意：需要根据实际阿里云实例规格调整，确保符合 8c8g 和 1:1 比例
    # 示例可能是 ecs.c7.2xlarge（如果配置为 8vCPU 8GB）或其他符合规格的实例类型
    echo "Error: INSTANCE_TYPE is required for AMD64 architecture" >&2
    echo "Please specify an instance type that meets 8c8g (8 CPU, 8GB RAM) and 1:1 ratio" >&2
    exit 1
  elif [[ "${ARCH}" == "arm64" ]]; then
    # ARM64 默认实例类型：需要 8c16g（8 核 16GB）规格
    # 限制为 ecs.c8y 或 ecs.c8r 实例族
    echo "Error: INSTANCE_TYPE is required for ARM64 architecture" >&2
    echo "Please specify an instance type from ecs.c8y or ecs.c8r family that meets 8c16g (8 CPU, 16GB RAM) and 1:2 ratio" >&2
    exit 1
  else
    echo "Error: Unsupported architecture: ${ARCH}" >&2
    exit 1
  fi
fi

# 验证必需参数
if [[ -z "${ALIYUN_ACCESS_KEY_ID}" ]]; then
  echo "Error: ALIYUN_ACCESS_KEY_ID is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_ACCESS_KEY_SECRET}" ]]; then
  echo "Error: ALIYUN_ACCESS_KEY_SECRET is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_REGION_ID}" ]]; then
  echo "Error: ALIYUN_REGION_ID is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_VPC_ID}" ]]; then
  echo "Error: ALIYUN_VPC_ID is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_SECURITY_GROUP_ID}" ]]; then
  echo "Error: ALIYUN_SECURITY_GROUP_ID is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_IMAGE_ID}" ]]; then
  echo "Error: ALIYUN_IMAGE_ID is required" >&2
  exit 1
fi

if [[ -z "${ALIYUN_VSWITCH_ID}" ]]; then
  echo "Error: ALIYUN_VSWITCH_ID is required" >&2
  exit 1
fi

# INSTANCE_TYPE 验证已在上面处理（如果未指定则使用默认值）

if [[ -z "${INSTANCE_NAME}" ]]; then
  echo "Error: INSTANCE_NAME is required" >&2
  exit 1
fi

# 配置 Aliyun CLI
export ALIBABA_CLOUD_ACCESS_KEY_ID="${ALIYUN_ACCESS_KEY_ID}"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="${ALIYUN_ACCESS_KEY_SECRET}"

# 构建 RunInstances 命令
CMD="aliyun ecs RunInstances \
  --RegionId ${ALIYUN_REGION_ID} \
  --ImageId ${ALIYUN_IMAGE_ID} \
  --InstanceType ${INSTANCE_TYPE} \
  --SecurityGroupId ${ALIYUN_SECURITY_GROUP_ID} \
  --VSwitchId ${ALIYUN_VSWITCH_ID} \
  --InstanceName ${INSTANCE_NAME} \
  --InstanceChargeType PostPaid \
  --SpotStrategy SpotAsPriceGo \
  --InternetChargeType PayByTraffic \
  --InternetMaxBandwidthOut 10"

# 添加 SSH 密钥对（如果提供）
if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
  CMD="${CMD} --KeyPairName ${ALIYUN_KEY_PAIR_NAME}"
fi

# 添加 User Data（如果提供）
# 优先使用文件方式，避免环境变量传递多行脚本的问题
if [[ -n "${USER_DATA_FILE}" && -f "${USER_DATA_FILE}" ]]; then
  # 从文件读取 User Data
  USER_DATA=$(cat "${USER_DATA_FILE}")
  echo "Using User Data from file: ${USER_DATA_FILE}"
elif [[ -n "${USER_DATA}" ]]; then
  # 从环境变量读取 User Data（向后兼容）
  echo "Using User Data from environment variable"
else
  USER_DATA=""
fi

if [[ -n "${USER_DATA}" ]]; then
  # 将 User Data 编码为 base64（阿里云要求）
  USER_DATA_B64=$(echo -n "${USER_DATA}" | base64 -w 0 2>/dev/null || echo -n "${USER_DATA}" | base64 | tr -d '\n')
  CMD="${CMD} --UserData ${USER_DATA_B64}"
fi

# 执行创建实例命令
echo "=== Creating Spot Instance ==="
echo "Instance Name: ${INSTANCE_NAME}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo "Region: ${ALIYUN_REGION_ID}"
echo "Architecture: ${ARCH}"
echo "VPC ID: ${ALIYUN_VPC_ID}"
echo "VSwitch ID: ${ALIYUN_VSWITCH_ID}"
echo "Security Group ID: ${ALIYUN_SECURITY_GROUP_ID}"
echo "Image ID: ${ALIYUN_IMAGE_ID}"
if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
  echo "Key Pair Name: ${ALIYUN_KEY_PAIR_NAME}"
fi

# 执行命令并捕获输出和错误
RESPONSE=$(eval "${CMD}" 2>&1)
EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "Error: Failed to create Spot instance (exit code: ${EXIT_CODE})" >&2
  echo "Command: ${CMD}" >&2
  echo "Response: ${RESPONSE}" >&2
  exit ${EXIT_CODE}
fi

# 检查响应是否为空
if [[ -z "${RESPONSE}" ]]; then
  echo "Error: Empty response from Aliyun CLI" >&2
  exit 1
fi

# 尝试使用 jq 提取实例 ID（如果可用）
if command -v jq &> /dev/null; then
  INSTANCE_ID=$(echo "${RESPONSE}" | jq -r '.InstanceIdSets.InstanceIdSet[0]' 2>/dev/null || echo "")
else
  # 如果没有 jq，使用 grep 和 cut
  INSTANCE_ID=$(echo "${RESPONSE}" | grep -o '"InstanceId":"[^"]*' | cut -d'"' -f4 || echo "")
fi

if [[ -z "${INSTANCE_ID}" || "${INSTANCE_ID}" == "null" ]]; then
  echo "Error: Failed to extract instance ID from response" >&2
  echo "Response: ${RESPONSE}" >&2
  exit 1
fi

echo "Spot instance created successfully: ${INSTANCE_ID}"

# 输出实例 ID（用于后续步骤）
echo "${INSTANCE_ID}"

