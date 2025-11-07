#!/bin/bash

# 自毁机制排查脚本
# 在 spot instance 内部运行此脚本来排查自毁机制问题

set -euo pipefail

echo "=========================================="
echo "自毁机制排查脚本"
echo "=========================================="
echo ""

# 1. 检查自毁脚本是否存在
echo "1. 检查自毁脚本是否存在"
SELF_DESTRUCT_SCRIPT="/usr/local/bin/self-destruct.sh"
if [[ -f "${SELF_DESTRUCT_SCRIPT}" ]]; then
    echo "   ✓ 自毁脚本存在: ${SELF_DESTRUCT_SCRIPT}"
    echo "   权限: $(ls -l "${SELF_DESTRUCT_SCRIPT}")"
else
    echo "   ✗ 自毁脚本不存在: ${SELF_DESTRUCT_SCRIPT}"
fi
echo ""

# 2. 检查 post-job hook 是否配置
echo "2. 检查 post-job hook 配置"
RUNNER_DIR="/opt/actions-runner"
POST_JOB_HOOK="${RUNNER_DIR}/post-job-hook.sh"
if [[ -f "${POST_JOB_HOOK}" ]]; then
    echo "   ✓ Post-job hook 脚本存在: ${POST_JOB_HOOK}"
    echo "   权限: $(ls -l "${POST_JOB_HOOK}")"
    echo "   内容:"
    cat "${POST_JOB_HOOK}" | sed 's/^/      /'
else
    echo "   ✗ Post-job hook 脚本不存在: ${POST_JOB_HOOK}"
fi

# 检查 .env 文件中的配置
if [[ -f "${RUNNER_DIR}/.env" ]]; then
    echo "   .env 文件中的相关配置:"
    grep -E "ACTIONS_RUNNER_HOOK_POST_JOB|POST_JOB" "${RUNNER_DIR}/.env" || echo "      未找到 POST_JOB 相关配置"
else
    echo "   ✗ .env 文件不存在: ${RUNNER_DIR}/.env"
fi
echo ""

# 3. 检查 systemd service 是否配置
echo "3. 检查 systemd service 配置"
SERVICE_FILE="/etc/systemd/system/self-destruct.service"
if [[ -f "${SERVICE_FILE}" ]]; then
    echo "   ✓ Systemd service 文件存在: ${SERVICE_FILE}"
    echo "   内容:"
    cat "${SERVICE_FILE}" | sed 's/^/      /'
    
    # 检查服务状态
    if systemctl is-enabled self-destruct.service &>/dev/null; then
        echo "   ✓ Service 已启用"
    else
        echo "   ✗ Service 未启用"
    fi
    
    if systemctl is-active self-destruct.service &>/dev/null; then
        echo "   ✓ Service 正在运行"
    else
        echo "   ⚠ Service 未运行（这是正常的，等待 Runner 服务停止）"
    fi
else
    echo "   ✗ Systemd service 文件不存在: ${SERVICE_FILE}"
fi
echo ""

# 4. 检查日志文件
echo "4. 检查日志文件"
LOG_FILE="/var/log/self-destruct.log"
if [[ -f "${LOG_FILE}" ]]; then
    echo "   ✓ 日志文件存在: ${LOG_FILE}"
    echo "   文件大小: $(du -h "${LOG_FILE}" | cut -f1)"
    echo "   最后 20 行:"
    tail -20 "${LOG_FILE}" | sed 's/^/      /'
else
    echo "   ⚠ 日志文件不存在: ${LOG_FILE}（自毁脚本尚未执行）"
fi
echo ""

# 5. 检查 aliyun cli 是否安装
echo "5. 检查 Aliyun CLI"
if command -v aliyun &> /dev/null; then
    echo "   ✓ Aliyun CLI 已安装"
    echo "   路径: $(which aliyun)"
    echo "   版本: $(aliyun --version 2>&1 | head -1 || echo '无法获取版本')"
else
    echo "   ✗ Aliyun CLI 未安装"
fi
echo ""

# 6. 检查实例角色配置
echo "6. 检查实例角色配置"
METADATA_URL="http://100.100.100.200/latest/meta-data"
INSTANCE_ID=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/instance-id" 2>/dev/null || echo "")
REGION_ID=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/region-id" 2>/dev/null || echo "")
RAM_ROLE=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/ram/security-credentials/" 2>/dev/null || echo "")

if [[ -n "${INSTANCE_ID}" ]]; then
    echo "   ✓ 实例 ID: ${INSTANCE_ID}"
else
    echo "   ✗ 无法获取实例 ID"
fi

if [[ -n "${REGION_ID}" ]]; then
    echo "   ✓ 区域 ID: ${REGION_ID}"
else
    echo "   ✗ 无法获取区域 ID"
fi

if [[ -n "${RAM_ROLE}" ]]; then
    echo "   ✓ 实例角色: ${RAM_ROLE}"
    
    # 尝试获取临时凭证
    CREDENTIALS=$(curl -s --connect-timeout 5 --max-time 10 "${METADATA_URL}/ram/security-credentials/${RAM_ROLE}" 2>/dev/null || echo "")
    if [[ -n "${CREDENTIALS}" ]]; then
        echo "   ✓ 可以获取临时凭证"
        echo "   凭证信息（前 100 字符）: ${CREDENTIALS:0:100}..."
    else
        echo "   ✗ 无法获取临时凭证"
    fi
else
    echo "   ✗ 未配置实例角色"
fi
echo ""

# 7. 检查 Runner 服务状态
echo "7. 检查 Runner 服务状态"
RUNNER_SERVICES=$(systemctl list-units --type=service --all | grep -E "actions\.runner" || echo "")
if [[ -n "${RUNNER_SERVICES}" ]]; then
    echo "   Runner 服务:"
    echo "${RUNNER_SERVICES}" | sed 's/^/      /'
    
    # 检查服务状态
    for service in $(systemctl list-units --type=service --all | grep -oE "actions\.runner\.[^ ]*\.service" || true); do
        if systemctl is-active "${service}" &>/dev/null; then
            echo "   ✓ ${service} 正在运行"
        else
            echo "   ⚠ ${service} 未运行"
        fi
    done
else
    echo "   ⚠ 未找到 Runner 服务"
fi
echo ""

# 8. 测试自毁脚本（不实际执行）
echo "8. 测试自毁脚本（语法检查）"
if [[ -f "${SELF_DESTRUCT_SCRIPT}" ]]; then
    if bash -n "${SELF_DESTRUCT_SCRIPT}" 2>&1; then
        echo "   ✓ 脚本语法正确"
    else
        echo "   ✗ 脚本语法错误:"
        bash -n "${SELF_DESTRUCT_SCRIPT}" 2>&1 | sed 's/^/      /'
    fi
else
    echo "   ✗ 脚本文件不存在，无法检查"
fi
echo ""

# 9. 检查环境变量
echo "9. 检查环境变量"
echo "   ACTIONS_RUNNER_HOOK_POST_JOB: ${ACTIONS_RUNNER_HOOK_POST_JOB:-未设置}"
if [[ -f "${RUNNER_DIR}/.env" ]]; then
    echo "   .env 文件中的环境变量:"
    grep -E "ACTIONS_RUNNER_HOOK|POST_JOB" "${RUNNER_DIR}/.env" | sed 's/^/      /' || echo "      未找到相关环境变量"
fi
echo ""

# 10. 手动测试 aliyun cli（不实际删除）
echo "10. 测试 Aliyun CLI 连接"
if command -v aliyun &> /dev/null; then
    echo "   测试获取实例信息（不删除）:"
    if [[ -n "${INSTANCE_ID}" && -n "${REGION_ID}" ]]; then
        # 先配置 Aliyun CLI 使用实例角色认证（如果未配置）
        RAM_ROLE_NAME=$(curl -s --connect-timeout 5 --max-time 10 "http://100.100.100.200/latest/meta-data/ram/security-credentials/" 2>/dev/null || echo "")
        if [[ -n "${RAM_ROLE_NAME}" ]]; then
            echo "   配置 Aliyun CLI 使用实例角色认证..."
            aliyun configure set \
                --mode EcsRamRole \
                --ram-role-name "${RAM_ROLE_NAME}" \
                --region "${REGION_ID}" 2>&1 | sed 's/^/      /' || echo "      配置失败，继续测试..."
        fi
        
        # 只查询实例信息，不删除
        RESPONSE=$(aliyun ecs DescribeInstances \
            --RegionId "${REGION_ID}" \
            --InstanceIds "[\"${INSTANCE_ID}\"]" 2>&1 || echo "ERROR")
        
        if [[ "${RESPONSE}" != "ERROR" && -n "${RESPONSE}" ]]; then
            # 尝试使用 jq 解析 JSON（如果可用）
            if command -v jq &> /dev/null; then
                STATUS=$(echo "${RESPONSE}" | jq -r '.Instances.Instance[0].Status' 2>/dev/null || echo "")
                if [[ -n "${STATUS}" && "${STATUS}" != "null" ]]; then
                    echo "   ✓ 可以访问 ECS API，实例状态: ${STATUS}"
                else
                    echo "   ✓ 可以访问 ECS API（响应格式可能不正确）"
                    echo "   响应前 200 字符: ${RESPONSE:0:200}..."
                fi
            else
                # 如果没有 jq，检查响应是否包含 JSON
                if echo "${RESPONSE}" | grep -q "InstanceId"; then
                    echo "   ✓ 可以访问 ECS API（响应包含实例信息）"
                else
                    echo "   ⚠ 可以访问 ECS API，但响应格式可能不正确"
                    echo "   响应前 200 字符: ${RESPONSE:0:200}..."
                fi
            fi
        else
            echo "   ✗ 无法访问 ECS API"
            echo "   错误信息: ${RESPONSE}"
        fi
    else
        echo "   ⚠ 缺少实例 ID 或区域 ID，无法测试"
    fi
else
    echo "   ✗ Aliyun CLI 未安装，无法测试"
fi
echo ""

# 11. 检查 User Data 日志
echo "11. 检查 User Data 日志"
USER_DATA_LOG="/var/log/user-data.log"
if [[ -f "${USER_DATA_LOG}" ]]; then
    echo "   ✓ User Data 日志存在: ${USER_DATA_LOG}"
    echo "   自毁机制相关日志:"
    grep -E "self-destruct|post-job|ACTIONS_RUNNER_HOOK" "${USER_DATA_LOG}" | tail -10 | sed 's/^/      /' || echo "      未找到相关日志"
else
    echo "   ⚠ User Data 日志不存在: ${USER_DATA_LOG}"
fi
echo ""

# 12. 检查 cloud-init 日志
echo "12. 检查 cloud-init 日志"
CLOUD_INIT_LOG="/var/log/cloud-init.log"
if [[ -f "${CLOUD_INIT_LOG}" ]]; then
    echo "   ✓ Cloud-init 日志存在: ${CLOUD_INIT_LOG}"
    echo "   最后 20 行:"
    tail -20 "${CLOUD_INIT_LOG}" | sed 's/^/      /'
else
    echo "   ⚠ Cloud-init 日志不存在: ${CLOUD_INIT_LOG}"
fi
echo ""

echo "=========================================="
echo "排查完成"
echo "=========================================="
echo ""
echo "如果发现问题，请检查："
echo "1. 自毁脚本是否存在且可执行"
echo "2. Post-job hook 是否配置在 .env 文件中"
echo "3. Systemd service 是否已启用"
echo "4. Aliyun CLI 是否已安装"
echo "5. 实例角色是否正确配置"
echo "6. 日志文件中的错误信息"
echo ""
echo "手动测试自毁脚本（不会实际删除实例）:"
echo "  sudo bash -x /usr/local/bin/self-destruct.sh"
echo ""
echo "查看完整日志:"
echo "  sudo tail -f /var/log/self-destruct.log"
echo "  sudo journalctl -u self-destruct.service -f"

