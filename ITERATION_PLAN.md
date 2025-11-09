# 多架构构建系统迭代计划

## 项目概述

使用 GitHub Actions 和阿里云 Spot 竞价实例，实现低成本、高性能的多架构（AMD64/ARM64）容器镜像自动化构建。

## 已完成迭代

### 迭代 1-3：基础构建工作流

- ✅ AMD64 构建工作流 (`build-amd64.yml`)
- ✅ Self-hosted Runner 配置
- ✅ Spot 实例创建和清理机制
- ✅ Runner 注册和上线检测
- ✅ Docker Buildx 配置
- ✅ 代理配置支持

### 迭代 4：迁移到 Self-hosted Runner

- ✅ 完善 Runner 配置（Ephemeral 模式）
- ✅ User Data 脚本优化
- ✅ 实例自毁机制（已实现）
- ✅ 错误处理和日志输出

### 迭代 5：多架构支持

- ✅ ARM64 构建工作流 (`build-arm64.yml`)
- ✅ 多架构镜像合并工作流 (`merge-manifests.yml`)
- ✅ 变量命名统一（`INSTANCE_TYPE_AMD64`、`INSTANCE_TYPE_ARM64`）
- ✅ 移除 Docker Hub 镜像默认值
- ✅ 条件步骤配置镜像

### 迭代 5.5：实例自毁机制实现 ✅

- ✅ 实例自毁脚本 (`self-destruct.sh`)
- ✅ Post-job hook 和 systemd service 双重触发机制
- ✅ 使用实例角色认证（无需 Access Key）
- ✅ 权限策略和配置文档完善
- ✅ 排查脚本和文档

### 迭代 6：动态实例选择 ✅

- ✅ 集成 `spot-instance-advisor` 工具，自动获取最新版本（v1.0.1 作为回退版本）
- ✅ 创建动态实例选择脚本 (`.github/scripts/select-instance.py`)
  - 支持 AMD64 和 ARM64 架构查询
  - AMD64: CPU:RAM = 1:1，8c8g 到 64c64g
  - ARM64: CPU:RAM = 1:2，8c16g 到 64c128g
  - 实现渐进式查询策略（精确匹配 -> 范围查询）
  - 支持多种 JSON 字段名格式（snake_case、PascalCase、camelCase）
  - 过滤实例（只保留符合最小要求的实例）
  - 计算 Spot 价格限制（最低总价的 120%）
  - 根据可用区映射 VSwitch ID
  - 生成候选结果文件（包含 VSwitch ID 和 Spot Price Limit）
  - 添加查询时间统计
- ✅ 更新 `build-amd64.yml` 和 `build-arm64.yml` 使用动态实例选择
  - 使用 `select-instance.py` 替换固定的 `INSTANCE_TYPE` 和 `VSWITCH_ID`
  - 支持失败重试机制（使用候选结果文件）
  - 使用 base64 编码传递 User Data，避免转义问题
- ✅ 创建 `write-user-data.py` 脚本
  - 从环境变量读取 base64 编码的 User Data
  - 解码并写入文件，避免在日志中暴露敏感信息
- ✅ 更新 `create-spot-instance.py`
  - 支持从候选结果文件读取并重试
  - 动态设置 Spot 策略（根据价格限制）
  - 添加 Aliyun CLI 配置验证
- ✅ 实现 Spot 价格限制
  - 根据查询结果计算最低总价（单核价格 × 总核数）
  - 自动设置 Spot 价格限制为最低总价的 120%
- ✅ 优化候选文件格式
  - 格式：`INSTANCE_TYPE|ZONE_ID|VSWITCH_ID|SPOT_PRICE_LIMIT|CPU_CORES`
  - 包含所有后续步骤需要的信息，避免重复计算和映射
- ✅ 处理空字符串输入（修复 workflow_dispatch inputs 可能返回空字符串的问题）

## 待完成迭代

### 迭代 8：并行度优化 ✅

**目标**：根据实例 CPU 核心数动态设置 `RESTY_J` 并行度，充分利用 CPU 资源。

**任务**：

1. ✅ 从实例类型提取 CPU 核心数（已在 select-instance.py 中实现）
   - 从 JSON 结果中提取 CPU 核心数
   - 或从实例类型名称解析核心数（如 `ecs.c7.2xlarge` → 8 核）

2. ✅ 传递 CPU 核心数到构建步骤
   - 在 `setup` job 的 `Select Optimal Instance` 步骤中，`select-instance.py` 已输出 `CPU_CORES`
   - 工作流自动解析并设置到 `$GITHUB_OUTPUT`
   - 在 `build` job 中使用 `${{ needs.setup.outputs.CPU_CORES }}` 设置 `RESTY_J`

3. ✅ 更新构建步骤
   - 在 `build-amd64.yml` 和 `build-arm64.yml` 的 `build` job 中
   - 将 `RESTY_J=8` 改为 `RESTY_J=${{ needs.setup.outputs.CPU_CORES }}`

**相关文件**：

- `.github/scripts/select-instance.py` (已实现 CPU 核心数提取，需要传递到构建步骤)
- `.github/workflows/build-amd64.yml` (修改)
- `.github/workflows/build-arm64.yml` (修改)

### 迭代 9：多架构合并自动化

**目标**：实现多架构镜像合并的自动化触发，无需手动触发。

**任务**：

1. 实现工作流依赖触发
   - 使用 `workflow_run` 触发器监听 AMD64 和 ARM64 构建完成
   - 或使用 `workflow_call` 在构建完成后自动调用合并工作流

2. 自动标签提取
   - 从触发的工作流中提取标签信息
   - 自动确定要合并的标签（去除架构后缀）

3. 条件合并
   - 检查两个架构的镜像是否都存在
   - 仅在两个镜像都存在时执行合并
   - 添加重试机制（如果镜像尚未推送完成）

**相关文件**：

- `.github/workflows/merge-manifests.yml` (修改)

### 迭代 10：测试和优化

**目标**：全面测试和性能优化。

**任务**：

1. 端到端测试
   - 测试完整的构建流程
   - 测试多架构合并流程
   - 测试错误处理和恢复机制

2. 性能优化
   - 优化构建时间
   - 优化实例选择算法
   - 优化缓存策略

3. 文档完善
   - 更新 README.md
   - 添加使用示例
   - 添加故障排查指南

**相关文件**：

- `README.md` (修改)
- 测试和文档

### 迭代 7：自动触发构建

**目标**：启用自动触发构建，支持分支推送和标签创建触发。

**任务**：

1. 启用 push 触发器
   - 在 `build-amd64.yml` 和 `build-arm64.yml` 中取消注释 `push` 触发器
   - 配置触发分支：`develop`、`master`
   - 配置触发路径（可选）：仅 Dockerfile 和相关文件变更时触发

2. 启用 tags 触发器
   - 取消注释 `tags` 触发器
   - 配置触发模式：`v*`（版本标签）

3. 优化触发逻辑
   - 确保两个工作流可以并行触发
   - 考虑使用 `workflow_call` 实现工作流复用（可选）

**相关文件**：

- `.github/workflows/build-amd64.yml` (修改)
- `.github/workflows/build-arm64.yml` (修改)

### 迭代 11：自定义镜像构建 ✅

**目标**：创建独立的工作流，基于阿里云 Ubuntu 24 最新镜像构建预装工具的自定义镜像（AMD64 和 ARM64），支持每日自动构建，使用 RAM 角色授权，并保存到 ECS 自定义镜像和镜像市场。

**任务**：

1. ✅ 创建镜像查询脚本
   - 使用 Aliyun CLI 查询指定 region 中 Ubuntu 24 的最新镜像
   - 支持 AMD64 和 ARM64 架构筛选
   - 返回镜像 ID、名称、创建时间、版本信息等
   - 生成版本标识（基于镜像 ID 和创建时间）

2. ✅ 创建镜像构建脚本
   - 创建临时 ECS 实例（基于查询到的最新 Ubuntu 24 镜像）
   - 通过 User Data 安装预装工具：
     - 基础工具：`curl`, `wget`, `git`, `jq`
     - Aliyun CLI（最新版本）
     - spot-instance-advisor（最新版本）
     - GitHub Actions Runner（预装但未配置，下载到 `/opt/actions-runner`）
   - 等待实例就绪和工具安装完成
   - 创建自定义镜像（`aliyun ecs CreateImage`）
   - 等待镜像创建完成（轮询镜像状态）
   - 清理临时实例
   - 实现版本检查逻辑：如果工具或基础镜像版本未变更，则跳过构建

3. ✅ 创建镜像发布脚本（可选）
   - 将自定义镜像发布到阿里云镜像市场
   - 支持公开或私有发布
   - 支持共享给特定账号

4. ✅ 创建工作流文件
   - 配置每日自动构建（UTC 时间 02:00，北京时间 10:00）
   - 支持手动触发（可强制构建）
   - 并行构建 AMD64 和 ARM64 镜像
   - 使用 RAM 角色授权（构建镜像时不需要，使用镜像时才需要）

**技术要点**：

- **版本检查**：基于基础镜像 ID 和创建时间生成版本哈希，检查是否已存在相同版本的自定义镜像
- **工具版本**：Aliyun CLI 和 spot-instance-advisor 自动获取最新版本，GitHub Actions Runner 使用可配置版本
- **RAM 角色**：构建镜像时不需要绑定 RAM 角色（工具安装不需要访问阿里云 API），使用镜像时才需要绑定
- **镜像命名**：包含架构信息、时间戳和版本哈希标签

**相关文件**：

- `.github/scripts/query-ubuntu-image.py` (新建)
- `.github/scripts/build-custom-image.py` (新建)
- `.github/scripts/publish-image-to-marketplace.py` (新建)
- `.github/workflows/build-custom-images.yml` (新建)

## 技术要点

### 动态实例选择

- 使用 `spot-instance-advisor` 工具查询价格
- 支持多可用区回退机制
- Spot 价格限制为最低总价的 120%
- 支持渐进式查询策略
- 候选文件包含 VSwitch ID 和 Spot Price Limit，避免重复计算

### 并行度优化

- `RESTY_J` 应等于实例 CPU 核心数
- 支持 8 核到 64 核的动态调整

### 工作流设计原则

- 避免在 workflow 中嵌入脚本
- 使用独立的脚本文件
- 清晰的职责分离

## 依赖关系

- 迭代 6 已完成（动态实例选择是基础）
- 迭代 8 依赖迭代 6（需要从动态选择中获取 CPU 核心数）
- 迭代 9 依赖迭代 7（需要自动触发构建）
- 迭代 10 应在所有迭代完成后进行
- 迭代 7 可以放在最后，因为自动触发构建不是核心功能

## 风险点

1. **spot-instance-advisor 工具可用性**：需要确保工具可以正常工作
2. **实例创建失败**：需要实现重试机制
3. **价格波动**：Spot 价格可能随时变化，需要合理设置价格限制
4. **可用区资源不足**：需要支持多可用区回退

## 实施任务清单

### 迭代 5.5：实例自毁机制实现 ✅

- [x] 创建实例自毁脚本 (.github/scripts/self-destruct.sh)，支持通过实例角色删除自身实例
- [x] 在 User Data 脚本中集成自毁机制，配置 Aliyun CLI 使用实例角色认证
- [x] 实现 Runner 退出时触发自毁脚本（使用 post-job hook 和 systemd service 双重机制）
- [x] 更新 create-spot-instance.sh 支持 RamRoleName 参数
- [x] 更新工作流传递 RamRoleName 到 User Data
- [x] 创建排查脚本和文档
- [x] 修复 post-job hook 配置时机和 systemd service 启动问题

### 迭代 6：动态实例选择 ✅

- [x] 集成 spot-instance-advisor 工具，在工作流中下载或使用预构建的二进制文件
- [x] 创建动态实例选择脚本 (.github/scripts/select-instance.py)，支持 AMD64 和 ARM64 架构查询
- [x] 更新 build-amd64.yml 和 build-arm64.yml 使用动态实例选择，替换固定的 INSTANCE_TYPE 和 VSWITCH_ID
- [x] 实现 Spot 价格限制（最低总价的 120%），更新 create-spot-instance.py
- [x] 创建 write-user-data.py 脚本，使用 base64 编码传递 User Data
- [x] 优化候选文件格式，包含 VSwitch ID 和 Spot Price Limit
- [x] 添加查询时间统计
- [x] 处理空字符串输入问题

### 迭代 8：并行度优化 ✅

- [x] 从实例类型提取 CPU 核心数（已在 select-instance.py 中实现）
- [x] 在 setup job 中捕获 CPU_CORES 并输出到 GitHub Actions outputs
- [x] 更新构建工作流，使用动态 CPU 核心数设置 RESTY_J 并行度

### 迭代 9：多架构合并自动化

- [ ] 实现多架构合并自动化触发，使用 workflow_run 监听构建完成
- [ ] 实现自动标签提取和条件合并逻辑

### 迭代 10：测试和优化

- [ ] 端到端测试完整构建流程和多架构合并流程
- [ ] 性能优化和文档完善

### 迭代 7：自动触发构建

- [ ] 启用 push 触发器，支持 develop 和 master 分支自动触发构建
- [ ] 启用 tags 触发器，支持 v* 版本标签自动触发构建

### 迭代 11：自定义镜像构建 ✅

- [x] 创建 query-ubuntu-image.py 脚本，查询阿里云 Ubuntu 24 最新镜像
- [x] 创建 build-custom-image.py 脚本，构建自定义镜像（包含工具安装逻辑）
- [x] 创建 publish-image-to-marketplace.py 脚本，发布镜像到市场（可选）
- [x] 创建 build-custom-images.yml 工作流，配置每日自动构建和手动触发
- [x] 实现版本检查逻辑，如果工具或基础镜像版本未变更，则跳过构建
