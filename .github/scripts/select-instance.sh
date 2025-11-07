#!/bin/bash

# 动态实例选择脚本
# 使用 spot-instance-advisor 工具查询价格最优的实例类型

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
ARCH="${ARCH:-amd64}"  # amd64 或 arm64
SPOT_ADVISOR_BINARY="${SPOT_ADVISOR_BINARY:-./spot-instance-advisor}"

# 验证必需参数
if [[ -z "${ALIYUN_ACCESS_KEY_ID}" ]]; then
  error_exit "ALIYUN_ACCESS_KEY_ID is required"
fi

if [[ -z "${ALIYUN_ACCESS_KEY_SECRET}" ]]; then
  error_exit "ALIYUN_ACCESS_KEY_SECRET is required"
fi

if [[ -z "${ALIYUN_REGION_ID}" ]]; then
  error_exit "ALIYUN_REGION_ID is required"
fi

# 验证架构参数
if [[ "${ARCH}" != "amd64" && "${ARCH}" != "arm64" ]]; then
  error_exit "ARCH must be either 'amd64' or 'arm64', got: ${ARCH}"
fi

# 检查 spot-instance-advisor 工具是否存在
if [[ ! -f "${SPOT_ADVISOR_BINARY}" ]]; then
  error_exit "spot-instance-advisor binary not found: ${SPOT_ADVISOR_BINARY}"
fi

# 检查工具是否可执行
if [[ ! -x "${SPOT_ADVISOR_BINARY}" ]]; then
  chmod +x "${SPOT_ADVISOR_BINARY}" || error_exit "Failed to make spot-instance-advisor executable"
fi

# 根据架构设置查询参数
# 从环境变量读取最小 CPU 和内存（如果未设置，使用默认值）
if [[ "${ARCH}" == "amd64" ]]; then
  # AMD64: CPU:RAM = 1:1，默认 8c8g 到 64c64g
  MIN_CPU="${MIN_CPU:-8}"
  MAX_CPU="${MAX_CPU:-64}"
  # 如果未设置 MIN_MEM，根据 MIN_CPU 计算（1:1 比例）
  if [[ -z "${MIN_MEM}" ]]; then
    MIN_MEM="${MIN_CPU}"
  else
    MIN_MEM="${MIN_MEM}"
  fi
  MAX_MEM="${MAX_MEM:-64}"
  ARCH_PARAM="x86_64"
  echo "Info: Querying for AMD64 instances (CPU:RAM = 1:1, ${MIN_CPU}c${MIN_MEM}g to ${MAX_CPU}c${MAX_MEM}g)" >&2
elif [[ "${ARCH}" == "arm64" ]]; then
  # ARM64: CPU:RAM = 1:2，默认 8c16g 到 64c128g
  MIN_CPU="${MIN_CPU:-8}"
  MAX_CPU="${MAX_CPU:-64}"
  # 如果未设置 MIN_MEM，根据 MIN_CPU 计算（1:2 比例）
  if [[ -z "${MIN_MEM}" ]]; then
    MIN_MEM=$((MIN_CPU * 2))
  else
    MIN_MEM="${MIN_MEM}"
  fi
  MAX_MEM="${MAX_MEM:-128}"
  ARCH_PARAM="arm64"
  echo "Info: Querying for ARM64 instances (CPU:RAM = 1:2, ${MIN_CPU}c${MIN_MEM}g to ${MAX_CPU}c${MAX_MEM}g)" >&2
fi

# 验证参数
if [[ ! "${MIN_CPU}" =~ ^[0-9]+$ ]] || [[ ! "${MAX_CPU}" =~ ^[0-9]+$ ]] || [[ ! "${MIN_MEM}" =~ ^[0-9]+$ ]] || [[ ! "${MAX_MEM}" =~ ^[0-9]+$ ]]; then
  error_exit "Invalid CPU or memory values: MIN_CPU=${MIN_CPU}, MAX_CPU=${MAX_CPU}, MIN_MEM=${MIN_MEM}, MAX_MEM=${MAX_MEM}"
fi

if [[ ${MIN_CPU} -gt ${MAX_CPU} ]]; then
  error_exit "MIN_CPU (${MIN_CPU}) must be less than or equal to MAX_CPU (${MAX_CPU})"
fi

if [[ ${MIN_MEM} -gt ${MAX_MEM} ]]; then
  error_exit "MIN_MEM (${MIN_MEM}) must be less than or equal to MAX_MEM (${MAX_MEM})"
fi

echo "Querying spot instances for architecture: ${ARCH}" >&2
echo "Region: ${ALIYUN_REGION_ID}" >&2
echo "CPU range: ${MIN_CPU}-${MAX_CPU} cores" >&2
echo "Memory range: ${MIN_MEM}-${MAX_MEM} GB" >&2

# 调用 spot-instance-advisor 工具
JSON_RESULT=$("${SPOT_ADVISOR_BINARY}" \
  -accessKeyId="${ALIYUN_ACCESS_KEY_ID}" \
  -accessKeySecret="${ALIYUN_ACCESS_KEY_SECRET}" \
  -region="${ALIYUN_REGION_ID}" \
  -mincpu="${MIN_CPU}" \
  -maxcpu="${MAX_CPU}" \
  -minmem="${MIN_MEM}" \
  -maxmem="${MAX_MEM}" \
  --json \
  --arch="${ARCH_PARAM}" 2>&1)

# 检查工具执行是否成功
if [[ $? -ne 0 ]]; then
  error_exit "spot-instance-advisor failed: ${JSON_RESULT}"
fi

# 检查 JSON 结果是否为空
if [[ -z "${JSON_RESULT}" ]]; then
  error_exit "spot-instance-advisor returned empty result"
fi

# 检查 jq 是否可用
if ! command -v jq &> /dev/null; then
  echo "Warning: jq is not available, using grep/sed as fallback" >&2
  USE_JQ=false
else
  USE_JQ=true
fi

# 解析 JSON 结果
if [[ "${USE_JQ}" == "true" ]]; then
  # 使用 jq 解析 JSON
  # 检查结果是否为数组
  if ! echo "${JSON_RESULT}" | jq -e '. | type == "array"' > /dev/null 2>&1; then
    error_exit "Invalid JSON format: expected array, got: $(echo "${JSON_RESULT}" | jq -r 'type')"
  fi

  # 检查数组是否为空
  ARRAY_LENGTH=$(echo "${JSON_RESULT}" | jq 'length')
  if [[ "${ARRAY_LENGTH}" -eq 0 ]]; then
    error_exit "No spot instances found matching the criteria"
  fi

  # 限制候选结果数量（最多 5 个，用于重试）
  MAX_CANDIDATES=5
  if [[ "${ARRAY_LENGTH}" -gt "${MAX_CANDIDATES}" ]]; then
    ARRAY_LENGTH=${MAX_CANDIDATES}
    echo "Warning: Limiting candidates to ${MAX_CANDIDATES} (found ${ARRAY_LENGTH} total)" >&2
  fi

  # 提取所有候选结果（按价格排序，已由工具完成）
  # 输出格式：每行一个候选结果，格式为 "INSTANCE_TYPE|ZONE_ID|PRICE_PER_CORE|CPU_CORES"
  # 支持多种字段名格式：snake_case, PascalCase, camelCase
  CANDIDATES_FILE=$(mktemp)
  for ((i=0; i<ARRAY_LENGTH; i++)); do
    INSTANCE_TYPE=$(echo "${JSON_RESULT}" | jq -r ".[${i}].instanceTypeId // .[${i}].instance_type // .[${i}].InstanceType // empty")
    ZONE_ID=$(echo "${JSON_RESULT}" | jq -r ".[${i}].zoneId // .[${i}].zone_id // .[${i}].ZoneId // empty")
    PRICE_PER_CORE=$(echo "${JSON_RESULT}" | jq -r ".[${i}].pricePerCore // .[${i}].price_per_core // .[${i}].PricePerCore // .[${i}].price // .[${i}].Price // empty")
    CPU_CORES=$(echo "${JSON_RESULT}" | jq -r ".[${i}].cpuCoreCount // .[${i}].cpu_cores // .[${i}].CpuCores // .[${i}].cores // .[${i}].Cores // empty")
    
    if [[ -n "${INSTANCE_TYPE}" && -n "${ZONE_ID}" && -n "${PRICE_PER_CORE}" ]]; then
      echo "${INSTANCE_TYPE}|${ZONE_ID}|${PRICE_PER_CORE}|${CPU_CORES}" >> "${CANDIDATES_FILE}"
    fi
  done

  # 提取第一个结果（价格最优）
  FIRST_CANDIDATE=$(head -1 "${CANDIDATES_FILE}")
  INSTANCE_TYPE=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f1)
  ZONE_ID=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f2)
  PRICE_PER_CORE=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f3)
  CPU_CORES=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f4)
else
  # 使用 grep/sed 作为备选方案
  # 对于重试机制，我们需要提取多个候选结果
  CANDIDATES_FILE=$(mktemp)
  CANDIDATE_COUNT=0
  MAX_CANDIDATES=5
  
  # 提取所有候选结果（最多 5 个）
  # 由于没有 jq，我们使用简单的文本处理来提取多个结果
  # 支持多种字段名格式：snake_case, PascalCase, camelCase
  INSTANCE_TYPES=$(echo "${JSON_RESULT}" | grep -o '"instanceTypeId":"[^"]*' | cut -d'"' -f4 || \
                   echo "${JSON_RESULT}" | grep -o '"instance_type":"[^"]*' | cut -d'"' -f4 || \
                   echo "${JSON_RESULT}" | grep -o '"InstanceType":"[^"]*' | cut -d'"' -f4 || echo "")
  ZONE_IDS=$(echo "${JSON_RESULT}" | grep -o '"zoneId":"[^"]*' | cut -d'"' -f4 || \
             echo "${JSON_RESULT}" | grep -o '"zone_id":"[^"]*' | cut -d'"' -f4 || \
             echo "${JSON_RESULT}" | grep -o '"ZoneId":"[^"]*' | cut -d'"' -f4 || echo "")
  PRICE_PER_CORES=$(echo "${JSON_RESULT}" | grep -o '"pricePerCore":[0-9.]*' | cut -d':' -f2 || \
                    echo "${JSON_RESULT}" | grep -o '"price_per_core":[0-9.]*' | cut -d':' -f2 || \
                    echo "${JSON_RESULT}" | grep -o '"PricePerCore":[0-9.]*' | cut -d':' -f2 || \
                    echo "${JSON_RESULT}" | grep -o '"price":[0-9.]*' | cut -d':' -f2 || echo "")
  CPU_CORES_LIST=$(echo "${JSON_RESULT}" | grep -o '"cpuCoreCount":[0-9]*' | cut -d':' -f2 || \
                   echo "${JSON_RESULT}" | grep -o '"cpu_cores":[0-9]*' | cut -d':' -f2 || \
                   echo "${JSON_RESULT}" | grep -o '"CpuCores":[0-9]*' | cut -d':' -f2 || \
                   echo "${JSON_RESULT}" | grep -o '"cores":[0-9]*' | cut -d':' -f2 || echo "")
  
  # 将结果转换为数组（使用换行符分隔）
  INSTANCE_TYPE_ARRAY=()
  ZONE_ID_ARRAY=()
  PRICE_PER_CORE_ARRAY=()
  CPU_CORES_ARRAY=()
  
  while IFS= read -r line; do
    [[ -n "${line}" ]] && INSTANCE_TYPE_ARRAY+=("${line}")
  done <<< "${INSTANCE_TYPES}"
  
  while IFS= read -r line; do
    [[ -n "${line}" ]] && ZONE_ID_ARRAY+=("${line}")
  done <<< "${ZONE_IDS}"
  
  while IFS= read -r line; do
    [[ -n "${line}" ]] && PRICE_PER_CORE_ARRAY+=("${line}")
  done <<< "${PRICE_PER_CORES}"
  
  while IFS= read -r line; do
    [[ -n "${line}" ]] && CPU_CORES_ARRAY+=("${line}")
  done <<< "${CPU_CORES_LIST}"
  
  # 组合候选结果（取最小长度，确保所有数组都有对应值）
  MIN_LENGTH=${#INSTANCE_TYPE_ARRAY[@]}
  [[ ${#ZONE_ID_ARRAY[@]} -lt ${MIN_LENGTH} ]] && MIN_LENGTH=${#ZONE_ID_ARRAY[@]}
  [[ ${#PRICE_PER_CORE_ARRAY[@]} -lt ${MIN_LENGTH} ]] && MIN_LENGTH=${#PRICE_PER_CORE_ARRAY[@]}
  [[ ${MIN_LENGTH} -gt ${MAX_CANDIDATES} ]] && MIN_LENGTH=${MAX_CANDIDATES}
  
  for ((i=0; i<MIN_LENGTH && i<MAX_CANDIDATES; i++)); do
    INSTANCE_TYPE="${INSTANCE_TYPE_ARRAY[$i]}"
    ZONE_ID="${ZONE_ID_ARRAY[$i]}"
    PRICE_PER_CORE="${PRICE_PER_CORE_ARRAY[$i]}"
    CPU_CORES="${CPU_CORES_ARRAY[$i]:-}"
    
    if [[ -n "${INSTANCE_TYPE}" && -n "${ZONE_ID}" && -n "${PRICE_PER_CORE}" ]]; then
      echo "${INSTANCE_TYPE}|${ZONE_ID}|${PRICE_PER_CORE}|${CPU_CORES}" >> "${CANDIDATES_FILE}"
      CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
    fi
  done
  
  # 提取第一个结果（价格最优）
  FIRST_CANDIDATE=$(head -1 "${CANDIDATES_FILE}")
  INSTANCE_TYPE=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f1)
  ZONE_ID=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f2)
  PRICE_PER_CORE=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f3)
  CPU_CORES=$(echo "${FIRST_CANDIDATE}" | cut -d'|' -f4)
fi

# 验证提取的字段
if [[ -z "${INSTANCE_TYPE}" ]]; then
  error_exit "Failed to extract instance type from JSON result"
fi

if [[ -z "${ZONE_ID}" ]]; then
  error_exit "Failed to extract zone ID from JSON result"
fi

if [[ -z "${PRICE_PER_CORE}" ]]; then
  error_exit "Failed to extract price per core from JSON result"
fi

if [[ -z "${CPU_CORES}" ]]; then
  # 如果无法从 JSON 提取 CPU 核心数，尝试从实例类型名称解析
  # 例如：ecs.c7.2xlarge -> 8 核（2xlarge = 2 * 4 = 8）
  if [[ "${INSTANCE_TYPE}" =~ \.([0-9]+)xlarge$ ]]; then
    MULTIPLIER="${BASH_REMATCH[1]}"
    CPU_CORES=$((MULTIPLIER * 4))
  elif [[ "${INSTANCE_TYPE}" =~ \.xlarge$ ]]; then
    CPU_CORES=4
  elif [[ "${INSTANCE_TYPE}" =~ \.large$ ]]; then
    CPU_CORES=2
  elif [[ "${INSTANCE_TYPE}" =~ \.medium$ ]]; then
    CPU_CORES=2
  else
    # 如果无法解析，使用 MIN_CPU 作为默认值（更合理，因为查询时已经指定了最小 CPU）
    # 如果 MIN_CPU 也未设置，则使用 8 作为最后的默认值
    CPU_CORES="${MIN_CPU:-8}"
    echo "Warning: Could not determine CPU cores from instance type, using MIN_CPU as default: ${CPU_CORES}" >&2
  fi
fi

# 计算总价和价格限制
# 使用 bc 进行浮点数计算（如果可用），否则使用 awk
if command -v bc &> /dev/null; then
  TOTAL_PRICE=$(echo "${PRICE_PER_CORE} * ${CPU_CORES}" | bc)
  SPOT_PRICE_LIMIT=$(echo "${TOTAL_PRICE} * 1.2" | bc)
else
  # 使用 awk 进行浮点数计算
  TOTAL_PRICE=$(awk "BEGIN {printf \"%.4f\", ${PRICE_PER_CORE} * ${CPU_CORES}}")
  SPOT_PRICE_LIMIT=$(awk "BEGIN {printf \"%.4f\", ${TOTAL_PRICE} * 1.2}")
fi

# 根据可用区映射 VSwitch ID
# 从可用区 ID 提取后缀（如 cn-hangzhou-k -> K）
ZONE_SUFFIX=$(echo "${ZONE_ID}" | sed 's/.*-\([a-z]\)$/\1/' | tr '[:lower:]' '[:upper:]')
VSWITCH_VAR="ALIYUN_VSWITCH_ID_${ZONE_SUFFIX}"
VSWITCH_ID="${!VSWITCH_VAR:-}"

if [[ -z "${VSWITCH_ID}" ]]; then
  error_exit "VSwitch ID not found for zone ${ZONE_ID} (variable: ${VSWITCH_VAR})"
fi

# 输出结果（用于 GitHub Actions 捕获）
echo "INSTANCE_TYPE=${INSTANCE_TYPE}"
echo "ZONE_ID=${ZONE_ID}"
echo "VSWITCH_ID=${VSWITCH_ID}"
echo "SPOT_PRICE_LIMIT=${SPOT_PRICE_LIMIT}"
echo "CPU_CORES=${CPU_CORES}"
echo "CANDIDATES_FILE=${CANDIDATES_FILE}"

# 输出调试信息到标准错误
echo "Selected instance (primary):" >&2
echo "  Type: ${INSTANCE_TYPE}" >&2
echo "  Zone: ${ZONE_ID}" >&2
echo "  VSwitch: ${VSWITCH_ID}" >&2
echo "  CPU Cores: ${CPU_CORES}" >&2
echo "  Price per core: ${PRICE_PER_CORE}" >&2
echo "  Total price: ${TOTAL_PRICE}" >&2
echo "  Spot price limit: ${SPOT_PRICE_LIMIT}" >&2
echo "  Candidates available: $(wc -l < "${CANDIDATES_FILE}")" >&2

