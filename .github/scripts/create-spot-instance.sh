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
ARCH="${ARCH:-amd64}"  # amd64 或 arm64

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

if [[ -z "${INSTANCE_TYPE}" ]]; then
  echo "Error: INSTANCE_TYPE is required" >&2
  exit 1
fi

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
if [[ -n "${USER_DATA}" ]]; then
  # 将 User Data 编码为 base64（阿里云要求）
  USER_DATA_B64=$(echo -n "${USER_DATA}" | base64 -w 0 2>/dev/null || echo -n "${USER_DATA}" | base64 | tr -d '\n')
  CMD="${CMD} --UserData ${USER_DATA_B64}"
fi

# 执行创建实例命令
echo "Creating Spot instance: ${INSTANCE_NAME}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo "Region: ${ALIYUN_REGION_ID}"
echo "Architecture: ${ARCH}"

RESPONSE=$(eval "${CMD}" 2>&1)
EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "Error: Failed to create instance" >&2
  echo "Response: ${RESPONSE}" >&2
  exit ${EXIT_CODE}
fi

# 提取实例 ID
INSTANCE_ID=$(echo "${RESPONSE}" | grep -o '"InstanceId":"[^"]*' | cut -d'"' -f4 || echo "")

if [[ -z "${INSTANCE_ID}" ]]; then
  echo "Error: Failed to extract instance ID from response" >&2
  echo "Response: ${RESPONSE}" >&2
  exit 1
fi

# 输出实例 ID（用于后续步骤）
echo "${INSTANCE_ID}"

