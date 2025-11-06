# 阿里云配置指南

## 概述

使用阿里云竞价实例按需创建 AMD64 和 ARM64 self-hosted runners，实现成本优化的原生多架构容器镜像构建。

## 实例选择

使用 [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor) 工具实时查询指定资源需求的竞价实例价格，将返回按价格排序的多个结果集合（JSON 格式），结果字段中包含实例类型、单核价格、总核数以及可用区等信息。

- 示例：`./spot-instance-advisor -accessKeyId=xxx -accessKeySecret=xxx -region=cn-hangzhou -mincpu=8 -maxcpu=8 -minmem=16 -maxmem=16 --json --arch=aarch64`
- 解释：在区域`cn-hangzhou`中，查询CPU规格为8核（最大最小相同即指定规格），内存大小为16G（最大最小相同即指定规格），且CPU架构为aarch64（与arm64等义，可混用）的竞价实例价格信息，且以JSON格式输出

查询参数：

```text
Usage of ./spot-instance-advisor:
  -accessKeyId string
     Your accessKeyId of cloud account
  -accessKeySecret string
     Your accessKeySecret of cloud account
  -arch string
     CPU architecture filter: x86_64 or arm64
  -json
     Output results in JSON format
  -maxcpu int
     Max cores of spot instances  (default 32)
  -maxmem int
     Max memory of spot instances (default 64)
  -mincpu int
     Min cores of spot instances (default 1)
  -minmem int
     Min memory of spot instances (default 2)
  -region string
     The region of spot instances (default "cn-hangzhou")
```

- 首先在 JSON 结果集中，选择价格最优的实例类型（同时也就选择了可用区）；
- 如果当前所选择的 JSON 结果无法创建实例（比如该可用区的该实例类型资源不足等），将顺序尝试下一个结果。

**工具集成**：

- 实时价格查询：使用 [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor) 获取准确的价格，查询时使用资源条件，即指定min/max的CPU核数/内存大小/CPU架构以及地域等参数查询
- 结果集中的价格信息为单核价格，需要乘以总核数得出总价
- Spot 价格限制：自动设置为最低总价的 120%

支持的实例族：

ARM64 架构：

- ARM64 架构最小 CPU/RAM 配比的实例，实际上只有两个实例规格族，即`ecs.c8y`和`ecs.c8r`，其规格配比均为 CPU:RAM = 1:2，所以在 `spot-instance-advisor` 参数指定时，应注意这一点，否则如果以 1:1 查询会没有结果

AMD64 架构：

- 无实例规格族限制，但在查询时，应将传递的CPU和RAM参数设置为 CPU:RAM = 1:1

**规格要求**：

- AMD64: CPU:RAM = 1:1 比例，8c8g 到 64c64g 规格范围，无实例族限制
- ARM64: CPU:RAM = 1:2 比例，8c16g 到 64c128g 规格范围，实际上限制为 `ecs.c8y,ecs.c8r` 实例族
- 可通过 `--arch` 参数传递 CPU 架构
- 动态选择：工具自动查询所有符合条件的实例类型并按每核心价格选择最优实例
- 无需预设：只传递资源需求参数，不硬编码具体的实例类型，完全由工具查询确定

## 配置步骤

### 1. 阿里云资源准备

#### 示例：创建 VPC 和 VSwitches

```bash
# 创建 VPC
aliyun vpc CreateVpc \
  --RegionId ${ALIYUN_REGION_ID} \
  --VpcName vpc-ci-runner \
  --CidrBlock 172.16.0.0/16

# 在多个可用区创建 VSwitches（支持动态可用区选择）
# AMD64 可用区
aliyun vpc CreateVSwitch \
  --RegionId ${ALIYUN_REGION_ID} \
  --VSwitchName vsw-ci-runner-b \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.1.0/24 \
  --ZoneId ${ALIYUN_REGION_ID}-b

# ... 其他可用区的 VSwitches
```

建议为可能命中的可用区预先建立好相应的 VPC 交换机。

以阿里云华东 1（杭州）区域为例，ARM64 实例仅在 B\J\K 可用区内有效。

#### 示例：创建安全组

```bash
# 创建安全组
aliyun ecs CreateSecurityGroup \
  --RegionId ${ALIYUN_REGION_ID} \
  --GroupName sg-ci-runner \
  --VpcId vpc-xxx \
  --Description "Security group for CI runners"

# 添加入站规则（如需 SSH 访问）
aliyun ecs AuthorizeSecurityGroup \
  --RegionId ${ALIYUN_REGION_ID} \
  --SecurityGroupId sg-xxx \
  --IpProtocol tcp \
  --PortRange 22/22 \
  --SourceCidrIp 0.0.0.0/0
```

### 2. GitHub Secrets 和 Variables 配置

#### Secrets（敏感信息）

在仓库设置中添加以下 Secrets（用于存储敏感认证信息）：

| Secret 名称 | 描述 | 示例值 |
|------------|------|--------|
| `ALIYUN_ACCESS_KEY_ID` | 阿里云 Access Key ID | LTAI5t... |
| `ALIYUN_ACCESS_KEY_SECRET` | 阿里云 Access Key Secret | xxx... |

#### Variables（非敏感配置）

在仓库设置中添加以下 Variables（用于存储非敏感但需要配置的信息）：

| Variable 名称 | 描述 | 示例值 |
|--------------|------|--------|
| `ALIYUN_REGION_ID` | 区域 ID | cn-hangzhou |
| `ALIYUN_SECURITY_GROUP_ID` | 安全组 ID | sg-xxx |
| `ALIYUN_VPC_ID` | VPC ID | vpc-xxx |
| `ALIYUN_VSWITCH_ID_B` | 可用区 `${ALIYUN_REGION_ID}-b` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_G` | 可用区 `${ALIYUN_REGION_ID}-g` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_H` | 可用区 `${ALIYUN_REGION_ID}-h` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_I` | 可用区 `${ALIYUN_REGION_ID}-i` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_J` | 可用区 `${ALIYUN_REGION_ID}-j` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_K` | 可用区 `${ALIYUN_REGION_ID}-k` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_ARM64_IMAGE_ID` | ARM64 镜像 ID（推荐 Ubuntu 24） | m-xxx |
| `ALIYUN_AMD64_IMAGE_ID` | AMD64 镜像 ID（推荐 Ubuntu 24） | m-xxx |
| `ALIYUN_KEY_PAIR_NAME` | 用于 root 访问的 SSH 密钥对名称 | my-key-pair |

### 3. 权限配置

#### 阿里云 RAM 权限策略

##### 最小权限策略（推荐）

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunInstances",
        "ecs:DescribeInstances",
        "ecs:DeleteInstance"
      ],
      "Resource": [
        "acs:ecs:${REGION_ID}:*:instance/ci-runner-*-spot-*",
        "acs:ecs:${REGION_ID}:*:image/*",
        "acs:ecs:${REGION_ID}:*:securitygroup/sg-*",
        "acs:ecs:${REGION_ID}:*:vswitch/vsw-*"
      ],
      "Condition": {
        "StringLike": {
          "ecs:InstanceName": "ci-runner-*-spot-*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeImages",
        "ecs:DescribeSecurityGroups",
        "ecs:DescribeVSwitches",
        "ecs:DescribeVpcs",
        "ecs:DescribeAvailableResource",
        "ecs:DescribeSpotPriceHistory"
      ],
      "Resource": "*"
    }
  ]
}
```

##### 区域隔离策略

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunInstances",
        "ecs:DescribeInstances",
        "ecs:DeleteInstance"
      ],
      "Resource": [
        "acs:ecs:${REGION_ID}:*:instance/ci-runner-*-spot-*",
        "acs:ecs:${REGION_ID}:*:image/*",
        "acs:ecs:${REGION_ID}:*:securitygroup/sg-*",
        "acs:ecs:${REGION_ID}:*:vswitch/vsw-*"
      ],
      "Condition": {
        "StringEquals": {
          "ecs:RegionId": "${REGION_ID}"
        },
        "StringLike": {
          "ecs:InstanceName": "ci-runner-*-spot-*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeImages",
        "ecs:DescribeSecurityGroups",
        "ecs:DescribeVSwitches",
        "ecs:DescribeVpcs",
        "ecs:DescribeAvailableResource",
        "ecs:DescribeSpotPriceHistory"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ecs:RegionId": "${REGION_ID}"
        }
      }
    }
  ]
}
```

#### GitHub 权限

- `contents: read` - 读取仓库内容
- `packages: write` - 推送镜像
- `actions: write` - 管理 runners

#### 权限说明

**所需的阿里云 API 权限**：

| API 权限 | 用途 | 工作流使用 | 实例角色使用 |
|---------|------|-----------|------------|
| `ecs:RunInstances` | 创建 spot 实例 | ✅ 所有构建工作流 | ❌ |
| `ecs:DescribeInstances` | 查询实例状态 | ✅ 清理和列表操作 | ❌ |
| `ecs:DeleteInstance` | 删除实例 | ✅ 清理工作流（兜底） | ✅ 实例自毁 |
| `ecs:DescribeAvailableResource` | 查询可用资源和可用区 | ✅ spot-instance-advisor + 动态可用区查询 | ❌ |
| `ecs:DescribeSpotPriceHistory` | 查询 spot 价格 | ✅ spot-instance-advisor | ❌ |
| `ecs:DescribeImages` | 查询镜像信息 | ✅ 镜像验证 | ❌ |
| `ecs:DescribeSecurityGroups` | 查询安全组 | ✅ 安全组验证 | ❌ |
| `ecs:DescribeVSwitches` | 查询 VSwitches | ✅ 网络验证 | ❌ |
| `ecs:DescribeVpcs` | 查询 VPCs | ✅ 网络验证 | ❌ |

**注意**：如果使用实例角色实现自毁机制，需要为实例角色授予 `ecs:DeleteInstance` 权限

#### 实例角色权限策略（用于实例自毁）

如果使用实例角色实现实例内部自毁机制，需要创建独立的 RAM 角色并授予以下权限：

**权限策略示例**：

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecs:DeleteInstance",
      "Resource": "acs:ecs:cn-hangzhou:*:instance/*",
      "Condition": {
        "StringEquals": {
          "acs:ResourceTag/GIHUB_RUNNER_TYPE": [
            "aliyun-ecs-spot"
          ]
        }
      }
    }
  ]
}
```

**策略说明**：

- **Action**: `ecs:DeleteInstance` - 允许删除 ECS 实例
- **Resource**: `acs:ecs:${REGION_ID}:*:instance/*` - 指定区域内的所有实例（根据实际区域替换 `${REGION_ID}`）
- **Condition**: 使用标签条件限制，只允许删除带有 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot` 标签的实例
  - 标签条件提供更细粒度的权限控制
  - 确保实例角色只能删除标记为 CI Runner 的实例，提高安全性

**实例标签配置**：

在创建 Spot 实例时，会自动添加以下标签：

- **标签 Key**: `GIHUB_RUNNER_TYPE`
- **标签 Value**: `aliyun-ecs-spot`

此标签用于权限策略的条件匹配，确保实例角色只能删除 CI Runner 实例。

**创建实例角色步骤**：

1. 在阿里云 RAM 控制台创建角色（如 `EcsSelfDestructRole`）
2. 为角色授予上述权限策略（使用标签条件）
3. 创建实例时通过 `--RamRoleName` 参数指定实例角色
4. 实例创建时会自动添加 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot` 标签

**注意事项**：

- 权限策略中的区域 ID（如 `cn-hangzhou`）需要根据实际使用的区域进行替换
- 标签 Key `GIHUB_RUNNER_TYPE` 是固定的，不要修改
- 标签 Value `aliyun-ecs-spot` 是固定的，不要修改
- 如果使用多个区域，需要为每个区域创建相应的权限策略

详细配置请参考 [自动清理机制](#自动清理机制) 章节。

**资源命名约定**：

- 实例：`ci-runner-{arch}-spot-{timestamp}`
- 安全组：`sg-ci-runner`
- VSwitch：`vsw-ci-runner-{region}-{zone}`
- VPC：`vpc-ci-runner`

## CPU 密集型构建优化

### OpenResty 构建特性

OpenResty 构建是典型的**CPU 密集型任务**，主要消耗：

- **OpenSSL 编译**：加密算法需要大量 CPU 计算
- **LuaJIT 编译**：JIT 编译器需要大量 CPU 资源  
- **Nginx 模块编译**：各种 C 模块编译过程
- **并行编译**：`make -j${RESTY_J}` 使用多核并行编译

### 并行度控制机制

#### Dockerfile 级别

```dockerfile
# Dockerfile 中的默认设置
ARG RESTY_J="8"  # 默认值匹配标准构建的 8 核实例

# 实际使用位置
&& make -j${RESTY_J} \           # OpenSSL 编译
&& make -j${RESTY_J} install_sw \ # OpenSSL 安装
&& CFLAGS="-g -O3" make -j${RESTY_J} \ # PCRE2 编译
&& make -j${RESTY_J} \           # OpenResty 编译
&& make -j${RESTY_J} install \   # OpenResty 安装
```

#### 工作流级别

```yaml
# 工作流中的动态覆盖
build-args: |
  RESTY_J=${CPU_CORES}  # RESTY_J 应等于实例 CPU 核心数
```

#### 并行度设置建议

**RESTY_J 应等于实例的 CPU 核心数**，以充分利用 CPU 资源进行并行编译。

| 实例核心数 | RESTY_J 值 | 使用场景 | 性能改进 |
|-----------|-----------|---------|---------|
| **8 核** | `RESTY_J=8` | 标准构建 | 基线 |
| **16 核** | `RESTY_J=16` | 高性能构建 | 2 倍改进 |
| **32 核** | `RESTY_J=32` | 超高性能 | 4 倍改进 |
| **64 核** | `RESTY_J=64` | 极致性能 | 8 倍改进 |

### 性能优化建议

1. **实例选择**：AMD64 无实例族限制，ARM64 限制为 `ecs.c8y,ecs.c8r` 系列
2. **并行度设置**：Dockerfile 默认 `RESTY_J=8`（匹配标准构建的 8 核实例），**工作流应动态设置 `RESTY_J` 等于实例 CPU 核心数**（16核→16，32核→32，64核→64）

## 自动清理机制

### 双重清理保障

项目采用**双重清理机制**，确保 ECS 实例在任何情况下都能被可靠清理：

1. **实例内部自毁脚本**（主要机制）：Runner 退出后自动删除实例，在 ECS 实例的 User Data 脚本中，配置 Runner 以 Ephemeral 模式运行，并在 Runner 退出后自动调用 Aliyun CLI 删除自身实例。
2. **工作流清理作业**（兜底机制）：作为最终确认和异常情况处理

### 实例内部自毁机制（主要机制）

#### 工作原理

1. **实例角色配置**：在创建 Spot 实例时，通过 `--RamRoleName` 参数指定实例角色
2. **标签标记**：实例创建时自动添加标签 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot`
3. **权限策略**：实例角色被授予删除带有该标签的实例的权限
4. **自毁脚本**：在 User Data 脚本中安装自毁脚本，通过 Runner 的 post-job hook 或 systemd service 触发
5. **自动删除**：Runner 退出后，自毁脚本使用实例角色权限自动删除自身实例

#### 实现细节

**自毁脚本位置**：`/usr/local/bin/self-destruct.sh`

**触发机制**：

- **主要方式**：Runner 的 post-job hook（`ACTIONS_RUNNER_HOOK_POST_JOB`）
- **备用方式**：systemd service（`self-destruct.service`）

**认证方式**：

- 使用实例角色（RamRoleName）获取权限
- 实例角色通过阿里云元数据服务自动获取，无需配置 Access Key

**权限控制**：

- 权限策略使用标签条件（`acs:ResourceTag/GIHUB_RUNNER_TYPE=aliyun-ecs-spot`）
- 确保实例角色只能删除标记为 CI Runner 的实例，提高安全性

#### 配置要求

1. **创建 RAM 角色**：在阿里云 RAM 控制台创建角色（如 `EcsSelfDestructRole`）
2. **授予权限策略**：为角色授予删除实例的权限（使用标签条件）
3. **配置变量**：在 GitHub Variables 中配置 `ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME`
4. **实例标签**：实例创建时自动添加 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot` 标签

#### 权限策略示例

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecs:DeleteInstance",
      "Resource": "acs:ecs:cn-hangzhou:*:instance/*",
      "Condition": {
        "StringEquals": {
          "acs:ResourceTag/GIHUB_RUNNER_TYPE": [
            "aliyun-ecs-spot"
          ]
        }
      }
    }
  ]
}
```

**策略说明**：

- **Action**: `ecs:DeleteInstance` - 允许删除 ECS 实例
- **Resource**: `acs:ecs:${REGION_ID}:*:instance/*` - 指定区域内的所有实例（根据实际区域替换 `${REGION_ID}`）
- **Condition**: 使用标签条件限制，只允许删除带有 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot` 标签的实例

**实例标签**：

- **标签 Key**: `GIHUB_RUNNER_TYPE`（固定值，不要修改）
- **标签 Value**: `aliyun-ecs-spot`（固定值，不要修改）
- 标签在创建实例时自动添加，用于权限策略的条件匹配

#### 优势

1. **安全性**：使用标签条件限制权限，只能删除标记为 CI Runner 的实例
2. **自动化**：无需手动干预，Runner 退出后自动删除实例
3. **可靠性**：双重触发机制（post-job hook + systemd service）确保自毁脚本执行
4. **成本控制**：避免实例长时间运行产生费用
