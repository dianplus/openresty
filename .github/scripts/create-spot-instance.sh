#!/bin/bash

# 创建阿里云 ECS Spot 实例
# 用于创建 Self-hosted Runner 实例

set -euo pipefail

# 启用调试模式（如果设置了 DEBUG 环境变量）
# 注意：不在脚本开头启用 set -x，避免输出敏感信息（如 User Data 内容）
# 如果需要调试，可以在特定位置临时启用
DEBUG_MODE="${DEBUG:-false}"

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
ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME="${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME:-}"
INSTANCE_TYPE="${INSTANCE_TYPE:-}"
INSTANCE_NAME="${INSTANCE_NAME:-}"
USER_DATA="${USER_DATA:-}"
USER_DATA_FILE="${USER_DATA_FILE:-}"
ARCH="${ARCH:-amd64}"  # amd64 或 arm64
SPOT_PRICE_LIMIT="${SPOT_PRICE_LIMIT:-}"  # Spot 价格限制（可选）
CANDIDATES_FILE="${CANDIDATES_FILE:-}"  # 候选实例文件（用于重试，可选）
MAX_RETRIES="${MAX_RETRIES:-5}"  # 最大重试次数（默认 5 次）

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

# 获取镜像 ID（支持镜像族系）
IMAGE_FAMILY="${ALIYUN_IMAGE_FAMILY:-}"

if [[ -n "${IMAGE_FAMILY}" ]]; then
  # 方式1：优先从镜像族系获取
  echo "Getting latest image from family: ${IMAGE_FAMILY}" >&2
  IMAGE_INFO=$(aliyun ecs DescribeImageFromFamily \
    --RegionId "${ALIYUN_REGION_ID}" \
    --ImageFamily "${IMAGE_FAMILY}" 2>&1)
  EXIT_CODE=$?
  
  if [[ ${EXIT_CODE} -eq 0 ]]; then
    # 解析 JSON 获取 ImageId
    # 优先使用 jq（如果可用），否则使用 grep/sed
    if command -v jq &> /dev/null; then
      IMAGE_ID=$(echo "${IMAGE_INFO}" | jq -r '.Image.ImageId // empty' 2>/dev/null)
    else
      # 使用 grep 和 sed 解析 JSON
      IMAGE_ID=$(echo "${IMAGE_INFO}" | grep -o '"ImageId"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"ImageId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    fi
    
    if [[ -n "${IMAGE_ID}" && "${IMAGE_ID}" != "null" && "${IMAGE_ID}" != "empty" ]]; then
      echo "Found latest image from family ${IMAGE_FAMILY}: ${IMAGE_ID}" >&2
      ALIYUN_IMAGE_ID="${IMAGE_ID}"
    else
      echo "Warning: Failed to parse image ID from family ${IMAGE_FAMILY}, falling back to ALIYUN_IMAGE_ID" >&2
    fi
  else
    echo "Warning: Failed to query image from family ${IMAGE_FAMILY} (exit code: ${EXIT_CODE}), falling back to ALIYUN_IMAGE_ID" >&2
    if [[ -n "${IMAGE_INFO}" ]]; then
      echo "Error output: ${IMAGE_INFO}" >&2
    fi
  fi
fi

# 方式2：从环境变量直接获取镜像 ID（向后兼容）
if [[ -z "${ALIYUN_IMAGE_ID}" ]]; then
  if [[ -n "${IMAGE_FAMILY}" ]]; then
    echo "Error: Failed to get image from family ${IMAGE_FAMILY} and ALIYUN_IMAGE_ID is not set" >&2
    exit 1
  else
    echo "Error: Either ALIYUN_IMAGE_FAMILY or ALIYUN_IMAGE_ID must be set" >&2
    exit 1
  fi
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
  --SystemDisk.Category cloud_essd \
  --SecurityEnhancementStrategy Deactive \
  --Tag.1.Key GIHUB_RUNNER_TYPE \
  --Tag.1.Value aliyun-ecs-spot"

# 添加 SSH 密钥对（如果提供）
if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
  CMD="${CMD} --KeyPairName ${ALIYUN_KEY_PAIR_NAME}"
fi

# 添加实例角色（如果提供，用于实例自毁）
if [[ -n "${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}" ]]; then
  CMD="${CMD} --RamRoleName ${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}"
fi

# 添加 Spot 策略和价格限制（如果提供）
# 如果设置了 SpotPriceLimit，使用 SpotWithPriceLimit；否则使用 SpotAsPriceGo
if [[ -n "${SPOT_PRICE_LIMIT}" ]]; then
  CMD="${CMD} --SpotStrategy SpotWithPriceLimit --SpotPriceLimit ${SPOT_PRICE_LIMIT}"
else
  CMD="${CMD} --SpotStrategy SpotAsPriceGo"
fi

# 注意：User Data 的 base64 编码将在单次尝试或重试循环内部进行，避免不必要的提前编码

# 添加 User Data（如果提供）
# 优先使用文件方式，避免环境变量传递多行脚本的问题
if [[ -n "${USER_DATA_FILE}" && -f "${USER_DATA_FILE}" ]]; then
  # 从文件读取 User Data，并规范化换行（去除 CRLF），避免 /bin/bash^M 导致 127
  # 临时禁用调试输出，避免输出 User Data 内容（包含敏感信息）
  set +x 2>/dev/null || true
  RAW_USER_DATA=$(cat "${USER_DATA_FILE}")
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    set -x
  fi
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

# 注意：User Data 的 base64 编码将在重试循环内部进行，避免不必要的提前编码

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
if [[ -n "${SPOT_PRICE_LIMIT}" ]]; then
  echo "Spot Price Limit: ${SPOT_PRICE_LIMIT}" >&2
fi

# 实现重试机制（如果有候选结果文件）
# 注意：如果有候选结果文件，直接进入重试逻辑，不执行单次尝试
if [[ -n "${CANDIDATES_FILE}" && -f "${CANDIDATES_FILE}" ]]; then
  # 读取候选结果
  CANDIDATES=()
  while IFS='|' read -r cand_instance_type cand_zone_id cand_price_per_core cand_cpu_cores; do
    if [[ -n "${cand_instance_type}" && -n "${cand_zone_id}" ]]; then
      CANDIDATES+=("${cand_instance_type}|${cand_zone_id}|${cand_price_per_core}|${cand_cpu_cores}")
    fi
  done < "${CANDIDATES_FILE}"
  
  CANDIDATE_COUNT=${#CANDIDATES[@]}
  echo "Found ${CANDIDATE_COUNT} candidate instances for retry" >&2
  
  # 尝试每个候选结果
  ATTEMPT=0
  for CANDIDATE in "${CANDIDATES[@]}"; do
    ATTEMPT=$((ATTEMPT + 1))
    
    # 解析候选结果
    CAND_INSTANCE_TYPE=$(echo "${CANDIDATE}" | cut -d'|' -f1)
    CAND_ZONE_ID=$(echo "${CANDIDATE}" | cut -d'|' -f2)
    CAND_PRICE_PER_CORE=$(echo "${CANDIDATE}" | cut -d'|' -f3)
    CAND_CPU_CORES=$(echo "${CANDIDATE}" | cut -d'|' -f4)
    
    # 根据可用区映射 VSwitch ID
    CAND_ZONE_SUFFIX=$(echo "${CAND_ZONE_ID}" | sed 's/.*-\([a-z]\)$/\1/' | tr '[:lower:]' '[:upper:]')
    CAND_VSWITCH_VAR="ALIYUN_VSWITCH_ID_${CAND_ZONE_SUFFIX}"
    CAND_VSWITCH_ID="${!CAND_VSWITCH_VAR:-}"
    
    # 调试信息：输出变量名和值（如果设置了 DEBUG）
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "Debug: Zone ${CAND_ZONE_ID} -> Suffix ${CAND_ZONE_SUFFIX} -> Variable ${CAND_VSWITCH_VAR} -> Value ${CAND_VSWITCH_ID}" >&2
    fi
    
    if [[ -z "${CAND_VSWITCH_ID}" ]]; then
      echo "Warning: VSwitch ID not found for zone ${CAND_ZONE_ID} (variable: ${CAND_VSWITCH_VAR}), skipping candidate ${ATTEMPT}" >&2
      # 如果设置了 DEBUG，输出所有可用的 VSwitch ID 变量
      if [[ "${DEBUG:-}" == "true" ]]; then
        echo "Debug: Available VSwitch ID variables:" >&2
        env | grep "^ALIYUN_VSWITCH_ID_" | sort >&2 || echo "  (none found)" >&2
      fi
      continue
    fi
    
    # 计算价格限制（如果提供了价格信息）
    if [[ -n "${CAND_PRICE_PER_CORE}" && -n "${CAND_CPU_CORES}" ]]; then
      if command -v bc &> /dev/null; then
        CAND_TOTAL_PRICE=$(echo "${CAND_PRICE_PER_CORE} * ${CAND_CPU_CORES}" | bc)
        CAND_SPOT_PRICE_LIMIT=$(echo "${CAND_TOTAL_PRICE} * 1.2" | bc)
      else
        CAND_TOTAL_PRICE=$(awk "BEGIN {printf \"%.4f\", ${CAND_PRICE_PER_CORE} * ${CAND_CPU_CORES}}")
        CAND_SPOT_PRICE_LIMIT=$(awk "BEGIN {printf \"%.4f\", ${CAND_TOTAL_PRICE} * 1.2}")
      fi
    else
      CAND_SPOT_PRICE_LIMIT="${SPOT_PRICE_LIMIT}"
    fi
    
    echo "Attempt ${ATTEMPT}/${CANDIDATE_COUNT}: Trying instance type ${CAND_INSTANCE_TYPE} in zone ${CAND_ZONE_ID}" >&2
    
    # 构建命令（使用候选实例类型和可用区）
    CMD_CAND="aliyun ecs RunInstances \
      --RegionId ${ALIYUN_REGION_ID} \
      --ImageId ${ALIYUN_IMAGE_ID} \
      --InstanceType ${CAND_INSTANCE_TYPE} \
      --SecurityGroupId ${ALIYUN_SECURITY_GROUP_ID} \
      --VSwitchId ${CAND_VSWITCH_ID} \
      --InstanceName ${INSTANCE_NAME} \
      --InstanceChargeType PostPaid \
      --SystemDisk.Category cloud_essd \
      --SecurityEnhancementStrategy Deactive \
      --Tag.1.Key GIHUB_RUNNER_TYPE \
      --Tag.1.Value aliyun-ecs-spot"
    
    # 添加 SSH 密钥对（如果提供）
    if [[ -n "${ALIYUN_KEY_PAIR_NAME}" ]]; then
      CMD_CAND="${CMD_CAND} --KeyPairName ${ALIYUN_KEY_PAIR_NAME}"
    fi
    
    # 添加实例角色（如果提供）
    if [[ -n "${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}" ]]; then
      CMD_CAND="${CMD_CAND} --RamRoleName ${ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME}"
    fi
    
    # 添加 Spot 策略和价格限制（如果提供）
    # 如果设置了 SpotPriceLimit，使用 SpotWithPriceLimit；否则使用 SpotAsPriceGo
    if [[ -n "${CAND_SPOT_PRICE_LIMIT}" ]]; then
      CMD_CAND="${CMD_CAND} --SpotStrategy SpotWithPriceLimit --SpotPriceLimit ${CAND_SPOT_PRICE_LIMIT}"
    else
      CMD_CAND="${CMD_CAND} --SpotStrategy SpotAsPriceGo"
    fi
    
    # 添加 User Data（如果提供）
    # 在每次尝试时进行 base64 编码，避免不必要的提前编码
    if [[ -n "${USER_DATA}" ]]; then
      # 临时禁用调试输出，避免输出 base64 编码的 User Data 内容
      set +x 2>/dev/null || true
      # 将 User Data 编码为 base64（阿里云要求）
      CAND_USER_DATA_B64=$(echo -n "${USER_DATA}" | base64 -w 0 2>/dev/null || echo -n "${USER_DATA}" | base64 | tr -d '\n')
      if [[ "${DEBUG_MODE}" == "true" ]]; then
        set -x
      fi
      if [[ -z "${CAND_USER_DATA_B64}" ]]; then
        echo "Error: Failed to encode User Data to base64 for candidate ${ATTEMPT}" >&2
        continue
      fi
      CMD_CAND="${CMD_CAND} --UserData ${CAND_USER_DATA_B64}"
    fi
    
    # 执行命令
    set +e  # 临时禁用 exit on error，以便捕获错误
    RESPONSE=$(eval "${CMD_CAND}" 2>&1)
    EXIT_CODE=$?
    set -e  # 重新启用 exit on error
    
    # 检查是否成功
    if [[ ${EXIT_CODE} -eq 0 && -n "${RESPONSE}" ]]; then
      # 尝试提取实例 ID
      if command -v jq &> /dev/null; then
        INSTANCE_ID=$(echo "${RESPONSE}" | jq -r '.InstanceIdSets.InstanceIdSet[0]' 2>/dev/null || echo "")
      else
        INSTANCE_ID=$(echo "${RESPONSE}" | grep -o '"InstanceId":"[^"]*' | cut -d'"' -f4 || echo "")
      fi
      
      if [[ -n "${INSTANCE_ID}" && "${INSTANCE_ID}" != "null" ]]; then
        echo "Spot instance created successfully on attempt ${ATTEMPT}: ${INSTANCE_ID}" >&2
        echo "Instance Type: ${CAND_INSTANCE_TYPE}" >&2
        echo "Zone: ${CAND_ZONE_ID}" >&2
        echo "VSwitch: ${CAND_VSWITCH_ID}" >&2
        echo "${INSTANCE_ID}"
        exit 0
      fi
    fi
    
    # 如果失败，记录错误并继续下一个候选
    echo "Attempt ${ATTEMPT} failed (exit code: ${EXIT_CODE})" >&2
    if [[ -n "${RESPONSE}" ]]; then
      echo "Response: ${RESPONSE:0:500}..." >&2
    fi
  done
  
  # 所有候选结果都失败了
  echo "Error: Failed to create Spot instance after ${CANDIDATE_COUNT} attempts" >&2
  exit 1
else
  # 没有候选结果文件，使用原始逻辑（单次尝试）
  # 编码 User Data 为 base64（仅在单次尝试时使用）
  if [[ -n "${USER_DATA}" ]]; then
    # 临时禁用调试输出，避免输出 base64 编码的 User Data 内容
    set +x 2>/dev/null || true
    # 将 User Data 编码为 base64（阿里云要求）
    USER_DATA_B64=$(echo -n "${USER_DATA}" | base64 -w 0 2>/dev/null || echo -n "${USER_DATA}" | base64 | tr -d '\n')
    if [[ "${DEBUG_MODE}" == "true" ]]; then
      set -x
    fi
    if [[ -z "${USER_DATA_B64}" ]]; then
      echo "Error: Failed to encode User Data to base64" >&2
      exit 1
    fi
    CMD="${CMD} --UserData ${USER_DATA_B64}"
  fi
  
  # 构建命令字符串（不包含 UserData，因为可能很长）
  CMD_DISPLAY="${CMD}"
  if [[ "${CMD_DISPLAY}" == *"--UserData"* ]]; then
    # 截断 UserData 部分用于显示
    CMD_DISPLAY=$(echo "${CMD_DISPLAY}" | sed 's/--UserData [^ ]*/--UserData <base64-encoded-data>/')
  fi
  echo "Executing command: ${CMD_DISPLAY}" >&2
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
fi

