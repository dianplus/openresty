# GitHub Workflows 配置

## 镜像构建工作流

项目提供 AMD64 和 ARM64 两个独立的构建工作流，支持原生多架构构建。

- 使用阿里云 spot 竞价实例按需创建云实例
- 原生架构构建，性能优异（无 QEMU 模拟开销）
- 构建完成后自动清理云实例
- 使用 Ephemeral Runner 模式确保环境隔离

构建工作流采用清晰的两阶段 Job 串联架构，确保职责分离和可观测性：

阶段 I: 资源管理

- **执行位置**: GitHub-Hosted Runner（官方免费或按量付费）
- **职责**:
  1. 获取 Runner Registration Token
  2. 调用 Aliyun CLI 创建 ECS Spot 实例
  3. 传递 User Data 脚本（包含 Runner 配置和自毁逻辑）
  4. **等待并检测 Runner 上线**：轮询检查 Runner 是否成功注册到 GitHub
  5. **超时处理**：如果超时未注册，清理实例并失败
- **输出**: `instance_id`、`runner_name`、`runner_online`（是否成功上线）等

阶段 II: 业务逻辑

- **执行位置**: Self-Hosted Runner（ECS Spot 实例）
- **职责**:
  1. 执行实际的构建、测试等 CI 步骤
  2. 推送镜像到 GitHub Container Registry
  3. Job 完成后，Runner 自动注销（Ephemeral 模式）
  4. 实例内部自毁脚本自动删除 ECS 实例

## 工作流设计原则

### 避免在 Workflow 中嵌入脚本

**原则**：应尽可能避免在 workflow 文件中嵌入 Shell 脚本或 Python 脚本等。

**原因**：

1. **降低复杂度**：避免在 YAML 中处理复杂的脚本逻辑，提高可读性和可维护性
2. **避免字符转义问题**：在 YAML 中嵌入脚本时，需要处理大量字符转义（如引号、换行符、特殊字符等），容易出错
3. **减少变量替换错误**：复杂的变量替换和字符串拼接容易引入潜在错误，难以调试和维护
4. **提高可维护性**：将脚本逻辑独立出来，便于测试、版本控制和代码审查

**适用场景**：

- **Workflow 步骤中的脚本**：应尽可能使用独立的脚本文件（如 `.github/scripts/` 目录），通过 `run: script.sh` 或 `run: python3 script.py` 调用
- **Cloud Init User Data**：作为特殊情况，User Data 脚本需要传递给云实例，应视具体情况处理：
  - 优先使用模板文件（如 `.github/templates/user-data.sh`）并通过变量替换生成
  - 如果必须动态生成，考虑使用独立的脚本或工具生成，而不是在 workflow 中直接嵌入
  - 确保正确处理特殊字符和变量替换

**例外情况**：

- 简单的单行命令或简单的条件判断可以直接在 workflow 中编写
- 对于 User Data 脚本，如果必须动态生成，应确保：
  - 使用模板文件而非直接拼接
  - 正确处理所有特殊字符转义
  - 进行充分的测试验证
