#!/usr/bin/env python3
"""
动态实例选择脚本
使用 spot-instance-advisor 工具查询价格最优的实例类型
"""

import os
import sys
import json
import subprocess
import tempfile
import re
import time
from typing import List, Dict, Optional, Tuple


def error_exit(message: str) -> None:
    """输出错误信息并退出"""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def get_env_var(name: str, default: Optional[str] = None) -> str:
    """获取环境变量"""
    value = os.environ.get(name, default)
    if value is None:
        error_exit(f"{name} is required")
    return value


def parse_cpu_from_instance_type(instance_type: str) -> Optional[int]:
    """从实例类型名称解析 CPU 核心数"""
    # 例如：ecs.c7.2xlarge -> 8 核（2xlarge = 2 * 4 = 8）
    match = re.search(r"\.(\d+)xlarge$", instance_type)
    if match:
        return int(match.group(1)) * 4

    if instance_type.endswith(".xlarge"):
        return 4
    elif instance_type.endswith(".large"):
        return 2
    elif instance_type.endswith(".medium"):
        return 2

    return None


def get_field_value(obj: Dict, *keys: str) -> Optional[str]:
    """从 JSON 对象中获取字段值，支持多种字段名格式"""
    for key in keys:
        if key in obj:
            value = obj[key]
            return str(value) if value is not None else None
    return None


def query_spot_instances(
    advisor_binary: str,
    access_key_id: str,
    access_key_secret: str,
    region: str,
    min_cpu: int,
    max_cpu: int,
    min_mem: int,
    max_mem: int,
    arch: str,
    exact_match: bool = False,
) -> Optional[List[Dict]]:
    """查询竞价实例"""
    cmd = [
        advisor_binary,
        f"-accessKeyId={access_key_id}",
        f"-accessKeySecret={access_key_secret}",
        f"-region={region}",
        f"-mincpu={min_cpu}",
        f"-maxcpu={max_cpu if not exact_match else min_cpu}",
        f"-minmem={min_mem}",
        f"-maxmem={max_mem if not exact_match else min_mem}",
        "-limit=5",
        "--json",
        f"--arch={arch}",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)

        if result.returncode != 0:
            return None

        if not result.stdout.strip():
            return None

        data = json.loads(result.stdout)
        if not isinstance(data, list) or len(data) == 0:
            return None

        return data
    except (json.JSONDecodeError, subprocess.SubprocessError) as e:
        print(f"Warning: Query failed: {e}", file=sys.stderr)
        return None


def filter_instances(
    instances: List[Dict],
    min_cpu: int,
    min_mem: int,
    arch: str,
    max_candidates: int = 5,
) -> List[Tuple[str, str, float, int]]:
    """过滤实例，只保留符合最小要求的实例"""
    candidates = []

    for instance in instances:
        instance_type = get_field_value(
            instance, "instanceTypeId", "instance_type", "InstanceType"
        )
        zone_id = get_field_value(instance, "zoneId", "zone_id", "ZoneId")
        price_per_core = get_field_value(
            instance, "pricePerCore", "price_per_core", "PricePerCore", "price", "Price"
        )
        cpu_cores = get_field_value(
            instance, "cpuCoreCount", "cpu_cores", "CpuCores", "cores", "Cores"
        )
        memory_size = get_field_value(
            instance, "memorySize", "memory_size", "MemorySize", "memory", "Memory"
        )

        # 验证必需字段
        if not instance_type or not zone_id or not price_per_core:
            continue

        # 解析 CPU 核心数
        if cpu_cores:
            try:
                cpu_cores = int(cpu_cores)
            except ValueError:
                cpu_cores = None

        if cpu_cores is None:
            cpu_cores = parse_cpu_from_instance_type(instance_type)
            if cpu_cores is None:
                print(
                    f"Warning: Could not determine CPU cores from instance type {instance_type}, skipping",
                    file=sys.stderr,
                )
                continue

        # 解析内存大小
        if memory_size:
            try:
                memory_size = int(float(memory_size))
            except ValueError:
                memory_size = None

        if memory_size is None:
            # 根据架构和 CPU 核心数估算内存
            if arch == "amd64":
                memory_size = cpu_cores  # 1:1
            elif arch == "arm64":
                memory_size = cpu_cores * 2  # 1:2
            else:
                memory_size = cpu_cores

        # 过滤：只保留符合最小要求的实例
        if cpu_cores < min_cpu or memory_size < min_mem:
            print(
                f"Info: Skipping instance {instance_type} ({cpu_cores}c{memory_size}g) - "
                f"below minimum requirements ({min_cpu}c{min_mem}g)",
                file=sys.stderr,
            )
            continue

        # 解析价格
        try:
            price_per_core = float(price_per_core)
        except ValueError:
            continue

        candidates.append((instance_type, zone_id, price_per_core, cpu_cores))

        if len(candidates) >= max_candidates:
            break

    return candidates


def get_vswitch_id(zone_id: str) -> Optional[str]:
    """根据可用区 ID 获取 VSwitch ID"""
    # 从可用区 ID 提取后缀（如 cn-hangzhou-k -> K）
    match = re.search(r"-([a-z])$", zone_id)
    if not match:
        return None

    zone_suffix = match.group(1).upper()
    vswitch_var = f"ALIYUN_VSWITCH_ID_{zone_suffix}"
    return os.environ.get(vswitch_var)


def main():
    """主函数"""
    # 从环境变量获取参数
    access_key_id = get_env_var("ALIYUN_ACCESS_KEY_ID")
    access_key_secret = get_env_var("ALIYUN_ACCESS_KEY_SECRET")
    region_id = get_env_var("ALIYUN_REGION_ID")
    arch = os.environ.get("ARCH", "amd64")
    advisor_binary = os.environ.get("SPOT_ADVISOR_BINARY", "./spot-instance-advisor")

    # 验证架构参数
    if arch not in ("amd64", "arm64"):
        error_exit(f"ARCH must be either 'amd64' or 'arm64', got: {arch}")

    # 检查 spot-instance-advisor 工具是否存在
    if not os.path.isfile(advisor_binary):
        error_exit(f"spot-instance-advisor binary not found: {advisor_binary}")

    if not os.access(advisor_binary, os.X_OK):
        os.chmod(advisor_binary, 0o755)

    # 根据架构设置查询参数
    # 处理空字符串的情况（GitHub Actions workflow_dispatch inputs 可能返回空字符串）
    min_cpu_str = os.environ.get("MIN_CPU", "").strip()
    min_cpu = int(min_cpu_str) if min_cpu_str else 8

    max_cpu_str = os.environ.get("MAX_CPU", "").strip()
    max_cpu = int(max_cpu_str) if max_cpu_str else 64

    min_mem_str = os.environ.get("MIN_MEM", "").strip()
    max_mem_str = os.environ.get("MAX_MEM", "").strip()

    if arch == "amd64":
        if min_mem_str:
            min_mem = int(min_mem_str)
        else:
            min_mem = min_cpu  # 1:1
        max_mem = int(max_mem_str) if max_mem_str else 64
        arch_param = "x86_64"
        print(
            f"Info: Querying for AMD64 instances (CPU:RAM = 1:1, {min_cpu}c{min_mem}g to {max_cpu}c{max_mem}g)",
            file=sys.stderr,
        )
    else:  # arm64
        if min_mem_str:
            min_mem = int(min_mem_str)
        else:
            min_mem = min_cpu * 2  # 1:2
        max_mem = int(max_mem_str) if max_mem_str else 128
        arch_param = "arm64"
        print(
            f"Info: Querying for ARM64 instances (CPU:RAM = 1:2, {min_cpu}c{min_mem}g to {max_cpu}c{max_mem}g)",
            file=sys.stderr,
        )

    # 验证参数
    if min_cpu > max_cpu:
        error_exit(
            f"MIN_CPU ({min_cpu}) must be less than or equal to MAX_CPU ({max_cpu})"
        )

    if min_mem > max_mem:
        error_exit(
            f"MIN_MEM ({min_mem}) must be less than or equal to MAX_MEM ({max_mem})"
        )

    print(f"Querying spot instances for architecture: {arch}", file=sys.stderr)
    print(f"Region: {region_id}", file=sys.stderr)
    print(f"Starting with minimum requirements: {min_cpu}c{min_mem}g", file=sys.stderr)

    # 记录查询开始时间
    query_start_time = time.time()

    # 定义查询策略（按优先级顺序）
    query_strategies = []

    if arch == "amd64":
        # AMD64 策略：1:1 -> 1:2 -> 16核1:1 -> 16核1:2
        query_strategies.append((min_cpu, min_cpu, True, "1:1"))
        if min_cpu <= 32:
            mem_1_2 = min_cpu * 2
            query_strategies.append((min_cpu, mem_1_2, True, "1:2"))
        if min_cpu < 16:
            query_strategies.append((16, 16, True, "1:1"))
        if min_cpu < 16:
            query_strategies.append((16, 32, True, "1:2"))
        # 最后备选：范围查询
        query_strategies.append((min_cpu, max_cpu, False, "range"))
    else:  # arm64
        # ARM64 策略：1:2 -> 范围查询
        mem_1_2 = min_cpu * 2
        query_strategies.append((min_cpu, mem_1_2, True, "1:2"))
        # 最后备选：范围查询
        query_strategies.append((min_cpu, max_cpu, False, "range"))

    # 尝试每个查询策略，直到找到结果
    json_result = None
    query_attempt = 0

    for strat_cpu, strat_mem, exact_match, desc in query_strategies:
        query_attempt += 1

        if exact_match:
            print(
                f"Attempt {query_attempt}: Exact match ({strat_cpu}c{strat_mem}g, {desc})",
                file=sys.stderr,
            )
        else:
            print(
                f"Attempt {query_attempt}: Range query ({strat_cpu}-{max_cpu}c, {min_mem}-{max_mem}g)",
                file=sys.stderr,
            )

        instances = query_spot_instances(
            advisor_binary,
            access_key_id,
            access_key_secret,
            region_id,
            strat_cpu,
            max_cpu if not exact_match else strat_cpu,
            strat_mem if exact_match else min_mem,
            max_mem if not exact_match else strat_mem,
            arch_param,
            exact_match=exact_match,
        )

        if instances:
            json_result = instances
            print(
                f"Success: Found results with strategy {query_attempt} ({strat_cpu}c{strat_mem}g)",
                file=sys.stderr,
            )
            break

    if not json_result:
        error_exit(
            "All query strategies failed. No spot instances found matching the criteria."
        )

    # 记录查询结束时间并计算耗时
    query_end_time = time.time()
    query_duration = query_end_time - query_start_time
    print(f"Query completed in {query_duration:.2f} seconds", file=sys.stderr)

    # 过滤实例
    candidates = filter_instances(json_result, min_cpu, min_mem, arch, max_candidates=5)

    if not candidates:
        error_exit(
            f"No instances found matching minimum requirements ({min_cpu}c{min_mem}g)"
        )

    # 选择第一个有 VSwitch ID 的结果（价格最优且可用区有 VSwitch）
    instance_type = None
    zone_id = None
    price_per_core = None
    cpu_cores = None
    vswitch_id = None

    for (
        cand_instance_type,
        cand_zone_id,
        cand_price_per_core,
        cand_cpu_cores,
    ) in candidates:
        cand_vswitch_id = get_vswitch_id(cand_zone_id)
        if cand_vswitch_id:
            # 找到第一个有 VSwitch ID 的候选结果
            instance_type = cand_instance_type
            zone_id = cand_zone_id
            price_per_core = cand_price_per_core
            cpu_cores = cand_cpu_cores
            vswitch_id = cand_vswitch_id
            break

    # 如果所有候选结果都没有 VSwitch ID，报错
    if not instance_type:
        error_exit(
            "No instances found with VSwitch ID configured. "
            "Please ensure VSwitch IDs are configured for at least one zone."
        )

    # 计算总价和价格限制
    total_price = price_per_core * cpu_cores
    spot_price_limit = total_price * 1.2

    # 创建候选结果文件
    # 格式：INSTANCE_TYPE|ZONE_ID|VSWITCH_ID|SPOT_PRICE_LIMIT|CPU_CORES
    # 包含所有后续步骤需要的信息，避免重复计算和映射
    candidates_file = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt")
    for (
        cand_instance_type,
        cand_zone_id,
        cand_price_per_core,
        cand_cpu_cores,
    ) in candidates:
        # 为每个候选计算 VSwitch ID 和 Spot Price Limit
        cand_vswitch_id = get_vswitch_id(cand_zone_id)
        if not cand_vswitch_id:
            # 跳过没有 VSwitch ID 的候选（会在后续步骤中被跳过）
            continue

        # 计算 Spot Price Limit
        cand_total_price = cand_price_per_core * cand_cpu_cores
        cand_spot_price_limit = cand_total_price * 1.2

        candidates_file.write(
            f"{cand_instance_type}|{cand_zone_id}|{cand_vswitch_id}|{cand_spot_price_limit:.4f}|{cand_cpu_cores}\n"
        )
    candidates_file.close()

    # 输出结果（用于 GitHub Actions 捕获）
    print(f"INSTANCE_TYPE={instance_type}")
    print(f"ZONE_ID={zone_id}")
    print(f"VSWITCH_ID={vswitch_id}")
    print(f"SPOT_PRICE_LIMIT={spot_price_limit:.4f}")
    print(f"CPU_CORES={cpu_cores}")
    print(f"CANDIDATES_FILE={candidates_file.name}")

    # 输出调试信息到标准错误
    print("Selected instance (primary):", file=sys.stderr)
    print(f"  Type: {instance_type}", file=sys.stderr)
    print(f"  Zone: {zone_id}", file=sys.stderr)
    print(f"  VSwitch: {vswitch_id}", file=sys.stderr)
    print(f"  CPU Cores: {cpu_cores}", file=sys.stderr)
    print(f"  Price per core: {price_per_core}", file=sys.stderr)
    print(f"  Total price: {total_price:.4f}", file=sys.stderr)
    print(f"  Spot price limit: {spot_price_limit:.4f}", file=sys.stderr)
    print(f"  Candidates available: {len(candidates)}", file=sys.stderr)


if __name__ == "__main__":
    main()
