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
  # 使用 ${MIN_MEM:-} 避免 set -u 报错
  if [[ -z "${MIN_MEM:-}" ]]; then
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
  # 使用 ${MIN_MEM:-} 避免 set -u 报错
  if [[ -z "${MIN_MEM:-}" ]]; then
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
echo "Starting with minimum requirements: ${MIN_CPU}c${MIN_MEM}g" >&2

# 优化查询策略：先精确查询，如果没有结果再逐步扩大范围
# 这样可以大幅减少查询时间（从55秒降到2-6秒）
# 策略：
# 1. 首先尝试精确匹配（MIN_CPU:MIN_MEM，按架构比例）
# 2. 如果没有结果，逐步扩大范围
# 3. 最多只需要5个候选结果用于重试

# 定义查询策略（按优先级顺序）
# 格式：每个策略是一个数组，包含 [CPU, MEM, TYPE, DESC]
# TYPE: "exact" 表示精确匹配，"range" 表示范围查询
QUERY_STRATEGIES=()

if [[ "${ARCH}" == "amd64" ]]; then
  # AMD64 策略：1:1 -> 1:2 -> 16核1:1 -> 16核1:2
  # 策略1: 精确匹配 1:1
  QUERY_STRATEGIES+=("${MIN_CPU}|${MIN_CPU}|exact|1:1")
  # 策略2: 精确匹配 1:2（如果内存需求允许）
  if [[ ${MIN_CPU} -le 32 ]]; then
    MEM_1_2=$((MIN_CPU * 2))
    QUERY_STRATEGIES+=("${MIN_CPU}|${MEM_1_2}|exact|1:2")
  fi
  # 策略3: 16核 1:1
  if [[ ${MIN_CPU} -lt 16 ]]; then
    QUERY_STRATEGIES+=("16|16|exact|1:1")
  fi
  # 策略4: 16核 1:2
  if [[ ${MIN_CPU} -lt 16 ]]; then
    QUERY_STRATEGIES+=("16|32|exact|1:2")
  fi
  # 策略5: 如果以上都失败，使用原始范围查询（作为最后备选）
  QUERY_STRATEGIES+=("${MIN_CPU}|${MAX_CPU}|${MIN_MEM}|${MAX_MEM}|range")
elif [[ "${ARCH}" == "arm64" ]]; then
  # ARM64 策略：1:2 -> 其他比例
  # 策略1: 精确匹配 1:2
  MEM_1_2=$((MIN_CPU * 2))
  QUERY_STRATEGIES+=("${MIN_CPU}|${MEM_1_2}|exact|1:2")
  # 策略2: 如果以上失败，使用原始范围查询（作为最后备选）
  QUERY_STRATEGIES+=("${MIN_CPU}|${MAX_CPU}|${MIN_MEM}|${MAX_MEM}|range")
fi

# 尝试每个查询策略，直到找到结果
JSON_RESULT=""
QUERY_ATTEMPT=0
for STRATEGY in "${QUERY_STRATEGIES[@]}"; do
  QUERY_ATTEMPT=$((QUERY_ATTEMPT + 1))
  
  # 解析策略参数（使用 | 分隔符避免与数字冲突）
  IFS='|' read -r STRAT_CPU STRAT_MEM STRAT_TYPE STRAT_DESC STRAT_MAX_CPU STRAT_MAX_MEM <<< "${STRATEGY}"
  
  if [[ "${STRAT_TYPE}" == "range" ]]; then
    # 范围查询（最后备选）
    # STRAT_CPU = MIN_CPU, STRAT_MEM = MAX_CPU, STRAT_DESC = MIN_MEM, STRAT_MAX_CPU = MAX_MEM
    echo "Attempt ${QUERY_ATTEMPT}: Range query (${STRAT_CPU}-${STRAT_MEM}c, ${STRAT_DESC}-${STRAT_MAX_CPU}g)" >&2
    JSON_RESULT=$("${SPOT_ADVISOR_BINARY}" \
      -accessKeyId="${ALIYUN_ACCESS_KEY_ID}" \
      -accessKeySecret="${ALIYUN_ACCESS_KEY_SECRET}" \
      -region="${ALIYUN_REGION_ID}" \
      -mincpu="${STRAT_CPU}" \
      -maxcpu="${STRAT_MEM}" \
      -minmem="${STRAT_DESC}" \
      -maxmem="${STRAT_MAX_CPU}" \
      -limit=5 \
      --json \
      --arch="${ARCH_PARAM}" 2>&1)
  else
    # 精确匹配查询
    echo "Attempt ${QUERY_ATTEMPT}: Exact match (${STRAT_CPU}c${STRAT_MEM}g, ${STRAT_DESC})" >&2
    JSON_RESULT=$("${SPOT_ADVISOR_BINARY}" \
      -accessKeyId="${ALIYUN_ACCESS_KEY_ID}" \
      -accessKeySecret="${ALIYUN_ACCESS_KEY_SECRET}" \
      -region="${ALIYUN_REGION_ID}" \
      -mincpu="${STRAT_CPU}" \
      -maxcpu="${STRAT_CPU}" \
      -minmem="${STRAT_MEM}" \
      -maxmem="${STRAT_MEM}" \
      -limit=5 \
      --json \
      --arch="${ARCH_PARAM}" 2>&1)
  fi
  
  # 检查工具执行是否成功
  if [[ $? -ne 0 ]]; then
    echo "Warning: Query attempt ${QUERY_ATTEMPT} failed: ${JSON_RESULT:0:200}..." >&2
    JSON_RESULT=""
    continue
  fi
  
  # 检查 JSON 结果是否为空或无效
  if [[ -z "${JSON_RESULT}" ]]; then
    echo "Warning: Query attempt ${QUERY_ATTEMPT} returned empty result" >&2
    continue
  fi
  
  # 检查结果是否为有效 JSON 数组且不为空
  if command -v jq &> /dev/null; then
    if ! echo "${JSON_RESULT}" | jq -e '. | type == "array" and length > 0' > /dev/null 2>&1; then
      echo "Warning: Query attempt ${QUERY_ATTEMPT} returned invalid or empty JSON array" >&2
      JSON_RESULT=""
      continue
    fi
  else
    # 如果没有 jq，简单检查是否包含实例类型
    if ! echo "${JSON_RESULT}" | grep -q "instanceTypeId"; then
      echo "Warning: Query attempt ${QUERY_ATTEMPT} returned no instance types" >&2
      JSON_RESULT=""
      continue
    fi
  fi
  
  # 找到有效结果，退出循环
  echo "Success: Found results with strategy ${QUERY_ATTEMPT} (${STRAT_CPU}c${STRAT_MEM}g)" >&2
  break
done

# 如果所有策略都失败，报错
if [[ -z "${JSON_RESULT}" ]]; then
  error_exit "All query strategies failed. No spot instances found matching the criteria."
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
  # 过滤结果：只保留符合 MIN_CPU 和 MIN_MEM 要求的实例
  CANDIDATES_FILE=$(mktemp)
  CANDIDATE_COUNT=0
  MAX_CANDIDATES=5
  
  # 从 JSON 结果中提取内存信息（用于过滤）
  for ((i=0; i<$(echo "${JSON_RESULT}" | jq 'length'); i++)); do
    INSTANCE_TYPE=$(echo "${JSON_RESULT}" | jq -r ".[${i}].instanceTypeId // .[${i}].instance_type // .[${i}].InstanceType // empty")
    ZONE_ID=$(echo "${JSON_RESULT}" | jq -r ".[${i}].zoneId // .[${i}].zone_id // .[${i}].ZoneId // empty")
    PRICE_PER_CORE=$(echo "${JSON_RESULT}" | jq -r ".[${i}].pricePerCore // .[${i}].price_per_core // .[${i}].PricePerCore // .[${i}].price // .[${i}].Price // empty")
    CPU_CORES=$(echo "${JSON_RESULT}" | jq -r ".[${i}].cpuCoreCount // .[${i}].cpu_cores // .[${i}].CpuCores // .[${i}].cores // .[${i}].Cores // empty")
    MEMORY_SIZE=$(echo "${JSON_RESULT}" | jq -r ".[${i}].memorySize // .[${i}].memory_size // .[${i}].MemorySize // .[${i}].memory // .[${i}].Memory // empty")
    
    # 验证必需字段
    if [[ -z "${INSTANCE_TYPE}" || -z "${ZONE_ID}" || -z "${PRICE_PER_CORE}" ]]; then
      continue
    fi
    
    # 如果无法从 JSON 提取 CPU 核心数，尝试从实例类型名称解析
    if [[ -z "${CPU_CORES}" ]]; then
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
        # 如果无法解析，跳过该实例
        echo "Warning: Could not determine CPU cores from instance type ${INSTANCE_TYPE}, skipping" >&2
        continue
      fi
    fi
    
    # 如果无法从 JSON 提取内存大小，尝试从实例类型名称解析（仅作为备选）
    if [[ -z "${MEMORY_SIZE}" ]]; then
      # 根据架构和 CPU 核心数估算内存（仅用于过滤，不用于实际选择）
      if [[ "${ARCH}" == "amd64" ]]; then
        # AMD64: CPU:RAM = 1:1
        MEMORY_SIZE="${CPU_CORES}"
      elif [[ "${ARCH}" == "arm64" ]]; then
        # ARM64: CPU:RAM = 1:2
        MEMORY_SIZE=$((CPU_CORES * 2))
      fi
    fi
    
    # 过滤：只保留符合 MIN_CPU 和 MIN_MEM 要求的实例
    if [[ ${CPU_CORES} -lt ${MIN_CPU} ]] || [[ ${MEMORY_SIZE} -lt ${MIN_MEM} ]]; then
      echo "Info: Skipping instance ${INSTANCE_TYPE} (${CPU_CORES}c${MEMORY_SIZE}g) - below minimum requirements (${MIN_CPU}c${MIN_MEM}g)" >&2
      continue
    fi
    
    # 添加到候选列表
    if [[ ${CANDIDATE_COUNT} -lt ${MAX_CANDIDATES} ]]; then
      echo "${INSTANCE_TYPE}|${ZONE_ID}|${PRICE_PER_CORE}|${CPU_CORES}" >> "${CANDIDATES_FILE}"
      CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
    else
      # 已达到最大候选数量
      break
    fi
  done
  
  # 检查是否有有效的候选结果
  if [[ ${CANDIDATE_COUNT} -eq 0 ]]; then
    error_exit "No instances found matching minimum requirements (${MIN_CPU}c${MIN_MEM}g)"
  fi

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
  
  # 提取内存信息（用于过滤）
  MEMORY_SIZES=$(echo "${JSON_RESULT}" | grep -o '"memorySize":[0-9.]*' | cut -d':' -f2 || \
                 echo "${JSON_RESULT}" | grep -o '"memory_size":[0-9.]*' | cut -d':' -f2 || \
                 echo "${JSON_RESULT}" | grep -o '"MemorySize":[0-9.]*' | cut -d':' -f2 || \
                 echo "${JSON_RESULT}" | grep -o '"memory":[0-9.]*' | cut -d':' -f2 || echo "")
  MEMORY_SIZE_ARRAY=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && MEMORY_SIZE_ARRAY+=("${line}")
  done <<< "${MEMORY_SIZES}"
  
  # 组合候选结果（取最小长度，确保所有数组都有对应值）
  MIN_LENGTH=${#INSTANCE_TYPE_ARRAY[@]}
  [[ ${#ZONE_ID_ARRAY[@]} -lt ${MIN_LENGTH} ]] && MIN_LENGTH=${#ZONE_ID_ARRAY[@]}
  [[ ${#PRICE_PER_CORE_ARRAY[@]} -lt ${MIN_LENGTH} ]] && MIN_LENGTH=${#PRICE_PER_CORE_ARRAY[@]}
  
  CANDIDATE_COUNT=0
  MAX_CANDIDATES=5
  
  for ((i=0; i<MIN_LENGTH && CANDIDATE_COUNT<MAX_CANDIDATES; i++)); do
    INSTANCE_TYPE="${INSTANCE_TYPE_ARRAY[$i]}"
    ZONE_ID="${ZONE_ID_ARRAY[$i]}"
    PRICE_PER_CORE="${PRICE_PER_CORE_ARRAY[$i]}"
    CPU_CORES="${CPU_CORES_ARRAY[$i]:-}"
    MEMORY_SIZE="${MEMORY_SIZE_ARRAY[$i]:-}"
    
    # 验证必需字段
    if [[ -z "${INSTANCE_TYPE}" || -z "${ZONE_ID}" || -z "${PRICE_PER_CORE}" ]]; then
      continue
    fi
    
    # 如果无法从 JSON 提取 CPU 核心数，尝试从实例类型名称解析
    if [[ -z "${CPU_CORES}" ]]; then
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
        # 如果无法解析，跳过该实例
        echo "Warning: Could not determine CPU cores from instance type ${INSTANCE_TYPE}, skipping" >&2
        continue
      fi
    fi
    
    # 如果无法从 JSON 提取内存大小，尝试从实例类型名称解析（仅作为备选）
    if [[ -z "${MEMORY_SIZE}" ]]; then
      # 根据架构和 CPU 核心数估算内存（仅用于过滤，不用于实际选择）
      if [[ "${ARCH}" == "amd64" ]]; then
        # AMD64: CPU:RAM = 1:1
        MEMORY_SIZE="${CPU_CORES}"
      elif [[ "${ARCH}" == "arm64" ]]; then
        # ARM64: CPU:RAM = 1:2
        MEMORY_SIZE=$((CPU_CORES * 2))
      fi
    fi
    
    # 过滤：只保留符合 MIN_CPU 和 MIN_MEM 要求的实例
    if [[ ${CPU_CORES} -lt ${MIN_CPU} ]] || [[ ${MEMORY_SIZE} -lt ${MIN_MEM} ]]; then
      echo "Info: Skipping instance ${INSTANCE_TYPE} (${CPU_CORES}c${MEMORY_SIZE}g) - below minimum requirements (${MIN_CPU}c${MIN_MEM}g)" >&2
      continue
    fi
    
    # 添加到候选列表
    echo "${INSTANCE_TYPE}|${ZONE_ID}|${PRICE_PER_CORE}|${CPU_CORES}" >> "${CANDIDATES_FILE}"
    CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
  done
  
  # 检查是否有有效的候选结果
  if [[ ${CANDIDATE_COUNT} -eq 0 ]]; then
    error_exit "No instances found matching minimum requirements (${MIN_CPU}c${MIN_MEM}g)"
  fi
  
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

