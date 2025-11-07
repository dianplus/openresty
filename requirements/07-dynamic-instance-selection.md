# 动态实例选择实现

## 概述

本文档描述了迭代“动态实例选择”的实现细节，作为需求文档的补充。

## 实现目标

使用 `spot-instance-advisor` 工具动态查询价格最优的实例类型，替代固定的实例类型配置，实现成本优化和可用性提升。

## 实现方案

### 1. spot-instance-advisor 工具集成

**工具下载**：

- 在工作流中从 GitHub releases 下载预构建二进制
- 自动获取最新 release 版本（使用 GitHub API）
- 如果获取失败，使用回退版本（v1.0.1）
- 确保工具可执行权限

**版本获取方式**：

- 使用 GitHub API 获取最新 release 标签：`https://api.github.com/repos/maskshell/spot-instance-advisor/releases/latest`
- 从响应中提取 `tag_name` 字段
- 如果 API 调用失败，使用回退版本 `v1.0.1`

**回退版本说明**：

- 选择 `v1.0.1` 作为回退版本的原因：从该版本开始支持 `--arch` 参数
- 这是支持架构参数的最低版本要求
- 确保即使 API 调用失败，也能使用支持架构参数的功能版本

**工具参数**：

- AMD64: `-mincpu=8 -maxcpu=64 -minmem=8 -maxmem=64 --arch=x86_64`
- ARM64: `-mincpu=8 -maxcpu=64 -minmem=16 -maxmem=128 --arch=arm64`

**JSON 输出格式**：

- 返回按价格排序的数组
- 每个结果包含：实例类型、可用区、单核价格、总核数等信息

### 2. 动态实例选择脚本

**文件**：`.github/scripts/select-instance.sh`

**功能**：

- 接收架构参数（amd64/arm64）
- 根据架构设置查询参数（CPU:RAM 比例、规格范围）
- 调用 `spot-instance-advisor` 工具
- 使用 `jq` 解析 JSON 结果（带 `grep/sed` 回退）
- 提取多个候选结果（最多 5 个，按价格排序）
- 选择价格最优的实例（第一个结果）
- 计算总价和价格限制（最低总价的 120%）
- 根据可用区映射 VSwitch ID
- 输出：实例类型、可用区、VSwitch ID、价格限制、CPU 核心数、候选结果文件

**输出格式**：

```text
INSTANCE_TYPE=ecs.c7.2xlarge
ZONE_ID=cn-hangzhou-k
VSWITCH_ID=vsw-xxx
SPOT_PRICE_LIMIT=0.12
CPU_CORES=8
CANDIDATES_FILE=/tmp/candidates-xxx.txt
```

**候选结果文件格式**：
每行一个候选结果，格式为：`INSTANCE_TYPE|ZONE_ID|PRICE_PER_CORE|CPU_CORES`

### 3. 失败重试机制

**实现方式**：

- `select-instance.sh` 返回多个候选结果（最多 5 个）
- `create-spot-instance.sh` 实现重试逻辑：
  - 如果有候选结果文件，依次尝试每个候选结果
  - 为每个候选结果计算价格限制和 VSwitch ID
  - 如果第一个失败，自动尝试下一个
  - 所有候选结果都失败后，返回错误

**重试逻辑**：

1. 读取候选结果文件
2. 遍历每个候选结果
3. 为每个候选结果构建创建命令
4. 执行创建命令
5. 如果成功，返回实例 ID
6. 如果失败，继续下一个候选结果

### 4. Spot 价格限制

**计算逻辑**：

- 总价 = 单核价格 × 总核数
- Spot 价格限制 = 总价 × 1.2（120%）

**实现方式**：

- 在 `select-instance.sh` 中计算价格限制
- 输出价格限制值到工作流
- 在 `create-spot-instance.sh` 中添加 `--SpotPriceLimit` 参数支持

### 5. VSwitch ID 动态映射

**映射逻辑**：

- 从可用区 ID 提取后缀（如 `cn-hangzhou-k` → `K`）
- 映射到环境变量：`ALIYUN_VSWITCH_ID_${ZONE_SUFFIX}`
- 支持多个可用区的 VSwitch ID 变量

**支持的可用区后缀**：

- A-Z（所有可能的可用区后缀，共 26 个）
- 根据实际使用的 region 配置相应的变量
- 未配置的变量为空值，脚本会自动跳过

### 6. CPU 核心数提取

**提取方式**：

- 优先从 JSON 结果中提取
- 如果无法提取，从实例类型名称解析：
  - `ecs.c7.2xlarge` → 8 核（2 × 4）
  - `ecs.c7.xlarge` → 4 核
  - `ecs.c7.large` → 2 核
- 如果无法解析，使用默认值 8 核

**用途**：

- 供迭代 8（并行度优化）使用
- 动态设置 `RESTY_J` 并行度

## 手动触发工作流

### workflow_dispatch 输入参数

当手动触发工作流时（`workflow_dispatch`），可以在 GitHub Actions UI 中输入以下参数：

**工作流输入参数**：

- `min_cpu` - 起始 CPU 核心数（可选，默认使用 `vars.MIN_CPU` 或 8）
- `min_mem` - 起始内存 GB（可选，默认根据 `min_cpu` 和架构自动计算）
  - AMD64: `min_mem = min_cpu`（1:1 比例）
  - ARM64: `min_mem = min_cpu * 2`（1:2 比例）

**注意**：

- `max_cpu` 和 `max_mem` 已移除，使用脚本默认值（64 和 64/128）
- 变量名已简化，去掉了架构前缀，因为工作流中已经有 `ARCH` 环境变量区分架构

**使用方式**：

1. 在 GitHub 仓库页面，进入 "Actions" 标签
2. 选择对应的工作流（"Build AMD64" 或 "Build ARM64"）
3. 点击 "Run workflow" 按钮
4. 在弹出窗口中输入起始核数等参数（可选）
5. 点击 "Run workflow" 开始执行

**示例**：

- 如果需要使用 4 核起始规格，在 `min_cpu` 输入框中输入 `4`
- 如果需要使用 16 核起始规格，在 `min_cpu` 输入框中输入 `16`
- 如果不输入任何值，将使用 GitHub Variables 中配置的值或默认值

**输入验证和错误处理**：

脚本会对输入值进行验证，如果输入无效值，工作流会在 "Select Optimal Instance" 步骤失败：

1. **小数输入**（如 `5.5`）：
   - GitHub Actions 的 `number` 类型会接受小数
   - 但脚本的正则验证 `^[0-9]+$` 只接受正整数
   - 结果：验证失败，报错 `Invalid CPU or memory values`
   - 工作流失败

2. **负数输入**（如 `-4`）：
   - GitHub Actions 的 `number` 类型会接受负数
   - 但脚本的正则验证 `^[0-9]+$` 只接受正整数
   - 结果：验证失败，报错 `Invalid CPU or memory values`
   - 工作流失败

3. **不存在的核数**（如 `3`）：
   - 格式验证通过（是正整数）
   - 但可能不是有效的实例规格
   - `spot-instance-advisor` 可能找不到匹配的实例
   - 结果：如果找不到匹配实例，报错 `No spot instances found matching the criteria`
   - 工作流失败

4. **超出范围的值**（如 `MIN_CPU=100 > MAX_CPU=64`）：
   - 脚本会验证 `MIN_CPU <= MAX_CPU`
   - 结果：验证失败，报错 `MIN_CPU must be less than or equal to MAX_CPU`
   - 工作流失败

5. **字符输入**（如 `abc`）：
   - GitHub Actions UI 中无法输入（`number` 类型限制）
   - 如果通过 API 或其他方式传入，脚本验证会失败
   - 结果：验证失败，报错 `Invalid CPU or memory values`
   - 工作流失败

6. **空字符串**：
   - 使用默认值（AMD64: 8, ARM64: 8）
   - 工作流正常执行

**建议**：

- 输入正整数（如 `4`、`8`、`16`、`32`）
- 确保 `MIN_CPU <= MAX_CPU`（默认 MAX_CPU=64）
- 使用常见的实例规格（如 2、4、8、16、32、64 核）

## 工作流集成

### 1. Download spot-instance-advisor 步骤

**位置**：`build-amd64.yml` 和 `build-arm64.yml` 的 `setup` job

**功能**：

- 从 GitHub releases 下载工具
- 设置可执行权限
- 输出工具路径

### 2. Select Optimal Instance 步骤

**位置**：`build-amd64.yml` 和 `build-arm64.yml` 的 `setup` job

**功能**：

- 调用 `select-instance.sh` 脚本
- 解析输出并设置 GitHub Actions 输出
- 将 `CANDIDATES_FILE` 导出到环境变量

**环境变量**：

- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `ALIYUN_REGION_ID`
- `ARCH`
- `SPOT_ADVISOR_BINARY`
- `ALIYUN_VSWITCH_ID_B` 到 `ALIYUN_VSWITCH_ID_K`（所有可用区）

### 3. Create Spot Instance 步骤

**位置**：`build-amd64.yml` 和 `build-arm64.yml` 的 `setup` job

**更新**：

- 使用动态值替换固定配置：
  - `INSTANCE_TYPE`: `${{ steps.select-instance.outputs.INSTANCE_TYPE }}`
  - `ALIYUN_VSWITCH_ID`: `${{ steps.select-instance.outputs.VSWITCH_ID }}`
  - `SPOT_PRICE_LIMIT`: `${{ steps.select-instance.outputs.SPOT_PRICE_LIMIT }}`
  - `CANDIDATES_FILE`: `${{ steps.select-instance.outputs.CANDIDATES_FILE }}`

## 技术要点

### JSON 处理

**使用 jq（推荐）**：

- 解析 JSON 数组
- 提取字段值
- 支持多种字段名称（`instance_type`/`InstanceType` 等）

**回退方案（grep/sed）**：

- 如果没有 `jq`，使用 `grep` 和 `cut` 提取字段
- 支持多个候选结果的提取

### 浮点数计算

**使用 bc（推荐）**：

- 计算总价和价格限制
- 支持浮点数运算

**回退方案（awk）**：

- 如果没有 `bc`，使用 `awk` 进行浮点数计算

### 错误处理

**验证机制**：

- 检查工具是否存在
- 检查 JSON 格式
- 检查提取的字段
- 检查 VSwitch ID 映射

**错误信息**：

- 详细的错误消息
- 调试信息输出到标准错误

## 文件清单

### 新建文件

- `.github/scripts/select-instance.sh` - 动态实例选择脚本

### 修改文件

- `.github/scripts/create-spot-instance.sh` - 添加价格限制和重试逻辑支持
- `.github/workflows/build-amd64.yml` - 集成动态实例选择
- `.github/workflows/build-arm64.yml` - 集成动态实例选择

## 配置要求

### GitHub Variables

**VSwitch ID 变量配置**：

由于不同 region 的可用区后缀可能不同（例如：cn-hangzhou 可能有 B/G/H/I/J/K，cn-beijing 可能有 A/B/C），工作流中预定义了所有可能的可用区后缀（A-Z）的环境变量。

**配置原则**：

- 根据实际使用的 region 配置相应的 VSwitch ID 变量
- 只需要配置实际使用的可用区的变量，未使用的可用区变量可以不配置（为空值）
- 脚本会自动跳过未配置的可用区变量

**示例配置**：

- 如果使用 `cn-hangzhou` region，可能需要配置：
  - `ALIYUN_VSWITCH_ID_B` - 可用区 `cn-hangzhou-b` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_G` - 可用区 `cn-hangzhou-g` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_H` - 可用区 `cn-hangzhou-h` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_I` - 可用区 `cn-hangzhou-i` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_J` - 可用区 `cn-hangzhou-j` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_K` - 可用区 `cn-hangzhou-k` 的 VSwitch ID

- 如果使用 `cn-beijing` region，可能需要配置：
  - `ALIYUN_VSWITCH_ID_A` - 可用区 `cn-beijing-a` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_B` - 可用区 `cn-beijing-b` 的 VSwitch ID
  - `ALIYUN_VSWITCH_ID_C` - 可用区 `cn-beijing-c` 的 VSwitch ID

**所有可用的变量名称**（A-Z）：

- `ALIYUN_VSWITCH_ID_A` 到 `ALIYUN_VSWITCH_ID_Z`（共 26 个变量）

### 资源需求规格变量（可选）

**变量配置**：

- `MIN_CPU` - 最小 CPU 核心数（可选，默认 8）

**配置说明**：

- 变量名已简化，去掉了架构前缀（`AMD64_`/`ARM64_`），因为工作流中已经有 `ARCH` 环境变量区分架构
- `MIN_MEM` 会根据 `MIN_CPU` 和架构自动计算：
  - AMD64: `MIN_MEM = MIN_CPU`（1:1 比例）
  - ARM64: `MIN_MEM = MIN_CPU * 2`（1:2 比例）
- `MAX_CPU` 和 `MAX_MEM` 使用脚本默认值（不需要配置）：
  - `MAX_CPU`: 64（固定上限）
  - `MAX_MEM`: AMD64 为 64，ARM64 为 128（固定上限）
- 如果未设置 `MIN_CPU`，使用默认值 8

**配置优先级**：

1. **workflow_dispatch inputs**（手动触发时输入的值，优先级最高）
2. **GitHub Variables**（仓库变量配置，变量名：`MIN_CPU`）
3. **默认值**（脚本内置默认值：8）

**示例配置**：

- **通过 GitHub Variables 配置**（适用于所有触发方式）：
  - 设置 `MIN_CPU=16`
  - AMD64: `MIN_MEM` 会自动设置为 16（1:1 比例），查询范围：16c16g 到 64c64g
  - ARM64: `MIN_MEM` 会自动设置为 32（1:2 比例），查询范围：16c32g 到 64c128g

- **通过 workflow_dispatch 手动输入**（仅适用于手动触发）：
  - 在 GitHub Actions UI 中手动触发工作流时，可以输入起始核数
  - 例如：输入 `min_cpu=4`，`MIN_MEM` 会根据架构自动计算
  - 如果同时设置了 GitHub Variables 和手动输入，手动输入的值会优先使用

### spot-instance-advisor 版本

当前默认版本：`v1.0.0`

**注意**：需要根据实际版本调整工作流中的 `ADVISOR_VERSION` 变量。

## 测试建议

### 1. 工具下载测试

- 验证工具可以正常下载
- 验证工具可执行权限

### 2. 实例选择测试

- 验证查询参数正确
- 验证 JSON 解析正确
- 验证候选结果提取正确

### 3. 重试机制测试

- 验证第一个候选结果失败时，能够自动尝试下一个
- 验证所有候选结果都失败时，能够正确返回错误

### 4. 价格限制测试

- 验证价格限制计算正确
- 验证价格限制传递到创建命令

### 5. VSwitch 映射测试

- 验证可用区到 VSwitch ID 的映射正确
- 验证多个可用区的 VSwitch ID 变量配置正确

## 已知限制

1. **候选结果数量**：最多 5 个候选结果，避免过多重试
2. **JSON 格式依赖**：依赖 `spot-instance-advisor` 工具的 JSON 输出格式
3. **可用区限制**：需要预先配置所有可能命中的可用区的 VSwitch ID

## 跨 Region 可用区支持

### 问题描述

不同 region 的可用区后缀可能不同：

- `cn-hangzhou` 可能有 B/G/H/I/J/K 可用区
- `cn-beijing` 可能有 A/B/C 可用区
- 其他 region 可能有不同的可用区后缀

### 解决方案

**预定义所有可能的可用区后缀（A-Z）**：

- 在工作流中预定义所有可能的可用区后缀（A-Z）的环境变量
- 根据实际使用的 region 配置相应的 VSwitch ID 变量
- 未配置的变量为空值，脚本会自动跳过

**优点**：

- 支持所有可能的可用区后缀（A-Z）
- 无需修改工作流代码，只需配置相应的变量
- 脚本自动处理未配置的变量

**缺点**：

- 工作流中需要声明所有可能的变量（A-Z，共 26 个）
- 即使不使用某些可用区，也需要在工作流中声明（但可以不配置值）

**替代方案**（未采用）：

1. **动态查询可用区**：使用 Aliyun CLI 动态查询可用区，但会增加复杂度和 API 调用
2. **JSON 配置映射**：使用 JSON 格式的配置映射，但需要额外的配置文件和解析逻辑
3. **按 region 分支**：为每个 region 创建不同的工作流分支，但会增加维护成本

**当前方案的选择理由**：

- 简单直接：预定义所有可能的变量，无需额外的查询或配置
- 可靠性高：不依赖额外的 API 调用或配置文件
- 易于维护：变量配置清晰，易于理解和维护
