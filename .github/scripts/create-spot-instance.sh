#!/bin/bash

# 创建阿里云 ECS Spot 实例
# 用于创建 Self-hosted Runner 实例

set -euo pipefail

# 启用调试模式（如果设置了 DEBUG 环境变量）
if [[ "${DEBUG:-}" == "true" ]]; then
  set -x
fi

# 错误处理函数
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

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

# 检查 Aliyun CLI 是否已安装
if ! command -v aliyun &> /dev/null; then
  echo "Error: Aliyun CLI is not installed or not in PATH" >&2
  echo "Please ensure aliyun-cli-setup-action is used in the workflow" >&2
  exit 1
fi

# 配置 Aliyun CLI
export ALIBABA_CLOUD_ACCESS_KEY_ID="${ALIYUN_ACCESS_KEY_ID}"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="${ALIYUN_ACCESS_KEY_SECRET}"

# 验证 Aliyun CLI 配置
echo "Verifying Aliyun CLI configuration..." >&2
if ! aliyun configure get &> /dev/null; then
  echo "Warning: Aliyun CLI configuration check failed, but continuing..." >&2
fi

# 构建 RunInstances 命令
# 注意：不创建公网IP，实例仅在内网访问
CMD="aliyun ecs RunInstances \
  --RegionId ${ALIYUN_REGION_ID} \
  --ImageId ${ALIYUN_IMAGE_ID} \
  --InstanceType ${INSTANCE_TYPE} \
  --SecurityGroupId ${ALIYUN_SECURITY_GROUP_ID} \
  --VSwitchId ${ALIYUN_VSWITCH_ID} \
  --InstanceName ${INSTANCE_NAME} \
  --InstanceChargeType PostPaid \
  --SpotStrategy SpotAsPriceGo \
  --SystemDisk.Category cloud_essd \
  --SecurityEnhancementStrategy Deactive"

# 添加 SSH 密钥对（如果提供）
if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
  CMD="${CMD} --KeyPairName ${ALIYUN_KEY_PAIR_NAME}"
fi

# 添加 User Data（如果提供）
# 优先使用文件方式，避免环境变量传递多行脚本的问题
if [[ -n "${USER_DATA_FILE}" && -f "${USER_DATA_FILE}" ]]; then
  # 从文件读取 User Data，并规范化换行（去除 CRLF），避免 /bin/bash^M 导致 127
  RAW_USER_DATA=$(cat "${USER_DATA_FILE}")
  USER_DATA=$(printf "%s" "${RAW_USER_DATA}" | sed 's/\r$//')
  USER_DATA_SIZE=$(printf "%s" "${USER_DATA}" | wc -c | awk '{print $1}')
  echo "Using User Data from file: ${USER_DATA_FILE} (${USER_DATA_SIZE} bytes, normalized)" >&2
elif [[ -n "${USER_DATA}" ]]; then
  # 从环境变量读取 User Data（向后兼容），并规范化换行
  USER_DATA=$(printf "%s" "${USER_DATA}" | sed 's/\r$//')
  USER_DATA_SIZE=${#USER_DATA}
  echo "Using User Data from environment variable (${USER_DATA_SIZE} bytes, normalized)" >&2
else
  USER_DATA=""
  echo "No User Data provided" >&2
fi

# 安全检查：确保存在 shebang，否则可能以 /bin/sh 执行导致失败
if [[ -n "${USER_DATA}" ]]; then
  FIRST_LINE=$(printf "%s" "${USER_DATA}" | head -n1)
  if [[ "${FIRST_LINE}" != "#!"* ]]; then
    echo "User Data missing shebang; prepending #!/bin/bash" >&2
    USER_DATA=$(printf "#!/bin/bash\n%s" "${USER_DATA}")
  fi
fi

if [[ -n "${USER_DATA}" ]]; then
  # 将 User Data 编码为 base64（阿里云要求）
  echo "Encoding User Data to base64..." >&2
  USER_DATA_B64=$(echo -n "${USER_DATA}" | base64 -w 0 2>/dev/null || echo -n "${USER_DATA}" | base64 | tr -d '\n')
  if [[ -z "${USER_DATA_B64}" ]]; then
    echo "Error: Failed to encode User Data to base64" >&2
    exit 1
  fi
  echo "User Data encoded successfully (${#USER_DATA_B64} bytes)" >&2
  CMD="${CMD} --UserData ${USER_DATA_B64}"
fi

# 执行创建实例命令
echo "=== Creating Spot Instance ===" >&2
echo "Instance Name: ${INSTANCE_NAME}" >&2
echo "Instance Type: ${INSTANCE_TYPE}" >&2
echo "Region: ${ALIYUN_REGION_ID}" >&2
echo "Architecture: ${ARCH}" >&2
echo "VPC ID: ${ALIYUN_VPC_ID}" >&2
echo "VSwitch ID: ${ALIYUN_VSWITCH_ID}" >&2
echo "Security Group ID: ${ALIYUN_SECURITY_GROUP_ID}" >&2
echo "Image ID: ${ALIYUN_IMAGE_ID}" >&2
if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
  echo "Key Pair Name: ${ALIYUN_KEY_PAIR_NAME}" >&2
fi

# 构建命令字符串（不包含 UserData，因为可能很长）
CMD_DISPLAY="${CMD}"
if [[ "${CMD_DISPLAY}" == *"--UserData"* ]]; then
  # 截断 UserData 部分用于显示
  CMD_DISPLAY=$(echo "${CMD_DISPLAY}" | sed 's/--UserData [^ ]*/--UserData <base64-encoded-data>/')
fi
echo "Executing command: ${CMD_DISPLAY}" >&2

# 执行命令并捕获输出和错误
# 注意：使用 eval 执行命令，确保所有参数正确传递
echo "About to execute Aliyun CLI command..." >&2
set +e  # 临时禁用 exit on error，以便捕获错误
RESPONSE=$(eval "${CMD}" 2>&1)
EXIT_CODE=$?
set -e  # 重新启用 exit on error

# 输出响应（用于调试）
echo "Command exit code: ${EXIT_CODE}" >&2
echo "Command response length: ${#RESPONSE} characters" >&2
if [[ -n "${RESPONSE}" ]]; then
  echo "Command response:" >&2
  echo "${RESPONSE}" >&2
else
  echo "Command response is empty" >&2
fi

if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "Error: Failed to create Spot instance (exit code: ${EXIT_CODE})" >&2
  echo "Full command: ${CMD_DISPLAY}" >&2
  echo "Full response: ${RESPONSE}" >&2
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

