# 阿里云配置指南

## 概述

使用阿里云竞价实例按需创建 AMD64 和 ARM64 self-hosted runners，实现成本优化的原生多架构容器镜像构建。

## 实例选择

使用 [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor) 工具实时查询指定资源需求的竞价实例价格，将返回按价格排序的多个结果集合（JSON 格式），结果字段中包含实例类型、单核价格、总核数以及可用区等信息。

- 示例：`./spot-instance-advisor -accessKeyId=xxx -accessKeySecret=xxx -region=cn-hangzhou -mincpu=8 -maxcpu=8 -minmem=16 -maxmem=16 --json --arch=aarch64`
- 说明：查询 `cn-hangzhou` 区域中 8 核 16G 的 ARM64 竞价实例价格（`aarch64` 与 `arm64` 等义）

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

**注意**：不同 region 的可用区后缀可能不同，需根据实际使用的 region 配置相应的 VSwitch ID 变量。例如 `cn-hangzhou` 可能需要配置 B/G/H/I/J/K，`cn-beijing` 可能需要配置 A/B/C。只需配置实际使用的可用区变量。

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
| `ALIYUN_VSWITCH_ID_A` | 可用区 `${ALIYUN_REGION_ID}-a` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_B` | 可用区 `${ALIYUN_REGION_ID}-b` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_C` | 可用区 `${ALIYUN_REGION_ID}-c` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_D` | 可用区 `${ALIYUN_REGION_ID}-d` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_E` | 可用区 `${ALIYUN_REGION_ID}-e` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_F` | 可用区 `${ALIYUN_REGION_ID}-f` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_G` | 可用区 `${ALIYUN_REGION_ID}-g` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_H` | 可用区 `${ALIYUN_REGION_ID}-h` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_I` | 可用区 `${ALIYUN_REGION_ID}-i` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_J` | 可用区 `${ALIYUN_REGION_ID}-j` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_K` | 可用区 `${ALIYUN_REGION_ID}-k` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_L` | 可用区 `${ALIYUN_REGION_ID}-l` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_M` | 可用区 `${ALIYUN_REGION_ID}-m` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_N` | 可用区 `${ALIYUN_REGION_ID}-n` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_O` | 可用区 `${ALIYUN_REGION_ID}-o` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_P` | 可用区 `${ALIYUN_REGION_ID}-p` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_Q` | 可用区 `${ALIYUN_REGION_ID}-q` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_R` | 可用区 `${ALIYUN_REGION_ID}-r` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_S` | 可用区 `${ALIYUN_REGION_ID}-s` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_T` | 可用区 `${ALIYUN_REGION_ID}-t` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_U` | 可用区 `${ALIYUN_REGION_ID}-u` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_V` | 可用区 `${ALIYUN_REGION_ID}-v` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_W` | 可用区 `${ALIYUN_REGION_ID}-w` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_X` | 可用区 `${ALIYUN_REGION_ID}-x` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_Y` | 可用区 `${ALIYUN_REGION_ID}-y` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_VSWITCH_ID_Z` | 可用区 `${ALIYUN_REGION_ID}-z` 的 VSwitch ID（可选） | vsw-xxx |
| `ALIYUN_ARM64_IMAGE_ID` | ARM64 镜像 ID（推荐 Ubuntu 24） | m-xxx |
| `ALIYUN_AMD64_IMAGE_ID` | AMD64 镜像 ID（推荐 Ubuntu 24） | m-xxx |
| `ALIYUN_KEY_PAIR_NAME` | 用于 root 访问的 SSH 密钥对名称 | my-key-pair |
| `MIN_CPU` | 实例最小 CPU 核心数（可选，默认 8） | 8 |
| `MIN_MEM` | 实例最小内存 GB（可选，默认根据 `MIN_CPU` 和架构自动计算） | 8 或 16 |

**注意**：

- 变量名已简化，去掉了架构前缀，因为工作流中已有 `ARCH` 环境变量区分架构
- `MIN_MEM` 会根据 `MIN_CPU` 和架构自动计算（AMD64: 1:1，ARM64: 1:2）
- 如需自定义 `MIN_MEM`，可单独配置
- `MAX_CPU` 和 `MAX_MEM` 使用脚本默认值（64 和 64/128），无需配置

### 3. 权限配置

#### 阿里云 RAM 权限策略

##### RAM 用户的推荐权限策略

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunInstances",
        "ecs:DescribeInstances",
        "ecs:DescribeImages",
        "ecs:DescribeSecurityGroups",
        "ecs:DescribeAvailableResource",
        "ecs:DescribeSpotPriceHistory"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "vpc:DescribeVSwitches",
        "vpc:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ram:PassRole",
      "Resource": "*"
    }
  ]
}
```

##### ECS实例角色推荐的策略

角色赋予给创建的 Runner Spot Instance，用于自毁。

角色的授权策略：

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DeleteInstance",
        "ecs:DeleteInstances"
      ],
      "Resource": "acs:ecs:*:*:instance/*",
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

角色的信任策略：

```json
{
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs.aliyuncs.com"
        ]
      }
    }
  ],
  "Version": "1"
}
```

#### GitHub 权限

- `contents: read` - 读取仓库内容
- `packages: write` - 推送镜像
- `actions: write` - 管理 runners

**实例标签配置**：

在创建 Spot 实例时，添加以下标签：

- **标签 Key**: `GIHUB_RUNNER_TYPE`
- **标签 Value**: `aliyun-ecs-spot`

此标签用于权限策略的条件匹配，确保实例角色只能删除 CI Runner 实例。

**创建实例角色步骤**：

1. 在阿里云 RAM 控制台创建角色（如 `GitHubRunnerSelfDestructRole`）
2. 为角色授予前述权限策略，以及信任策略
3. 创建实例时通过 `--RamRoleName` 参数指定实例角色
4. 实例创建时添加 `GIHUB_RUNNER_TYPE=aliyun-ecs-spot` 标签

**资源命名约定**：

- 实例：`ci-runner-{arch}-spot-{timestamp}`
- 安全组：`sg-ci-runner`
- VSwitch：`vsw-ci-runner-{region}-{zone}`
- VPC：`vpc-ci-runner`

## CPU 密集型构建优化

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

## 自动清理机制

### 双重清理保障

项目采用**双重清理机制**，确保 ECS 实例在任何情况下都能被可靠清理：

1. **实例内部自毁脚本**（主要机制）：Runner 退出后自动删除实例，在 ECS 实例的 User Data 脚本中，配置 Runner 以 Ephemeral 模式运行，并在 Runner 退出后自动调用 Aliyun CLI 删除自身实例。
2. **工作流清理作业**（兜底机制）：作为最终确认和异常情况处理

### 实例内部自毁机制（主要机制）

#### 工作原理

1. **实例角色配置**：在创建 Spot 实例时，通过 `--RamRoleName` 参数指定实例角色
2. **权限策略**：实例角色被授予删除带有该标签的实例的权限
3. **自毁脚本**：在 User Data 脚本中安装自毁脚本，通过 Runner 的 post-job hook 或 systemd service 触发
4. **自动删除**：Runner 退出后，自毁脚本使用实例角色权限自动删除自身实例

#### 实现细节

**自毁脚本位置**：`/usr/local/bin/self-destruct.sh`

**触发机制**：

- **主要方式**：Runner 的 post-job hook（`ACTIONS_RUNNER_HOOK_POST_JOB`）
- **备用方式**：systemd service（`self-destruct.service`）

**认证方式**：

- 使用实例角色（RamRoleName）获取权限
- 实例角色通过阿里云元数据服务自动获取，无需配置 Access Key
