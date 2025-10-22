# Aliyun Spot Instance Self-Hosted Runner Configuration Guide

## Overview

Use Aliyun spot instances to create AMD64 and ARM64 self-hosted runners on-demand, achieving cost-optimized native multi-architecture builds.

Supports multi-architecture manifests that point the same tag (e.g., `v1.0.0` or `latest`) to both AMD64 and ARM64 images, allowing users to directly `docker pull ghcr.io/dianplus/openresty:<tag>` for automatic platform-specific pulls.

## Architecture Support

## Architecture Support Comparison

| Feature | AMD64 Cloud Instance | ARM64 Cloud Instance | GitHub Runner |
|---------|---------------------|---------------------|---------------|
| **Build Speed** | 15-20 minutes | 15-20 minutes | 15-20 minutes |
| **Single Build Cost** | ¥0.05-0.1 | ¥0.05-0.1 | ¥0.2-0.4 |
| **Instance Type** | Dynamic Selection* | Dynamic Selection* | ubuntu-latest |
| **Native Support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Multi-Architecture** | ❌ AMD64 Only | ❌ ARM64 Only | ✅ Supported |
| **QEMU Emulation** | ❌ Not Required | ❌ Not Required | ⚠️ Required for ARM64 |
| **Image Tags** | `<tag>-amd64` | `<tag>-arm64` | Multi-Architecture |

*Dynamically query optimal instance types through [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor) tool

## Availability Zone Support

### ARM64 Architecture Availability Zones

In Aliyun East China 1 (Hangzhou) region, ARM64 architecture instances are only available in the following zones:

- `cn-hangzhou-b` - East China 1 Zone B ✅
- `cn-hangzhou-j` - East China 1 Zone J ✅  
- `cn-hangzhou-k` - East China 1 Zone K ✅

### AMD64 Architecture Availability Zones

AMD64 architecture instances are available in the following zones:

- `cn-hangzhou-b` - East China 1 Zone B ✅
- `cn-hangzhou-g` - East China 1 Zone G ✅
- `cn-hangzhou-h` - East China 1 Zone H ✅
- `cn-hangzhou-i` - East China 1 Zone I ✅
- `cn-hangzhou-j` - East China 1 Zone J ✅
- `cn-hangzhou-k` - East China 1 Zone K ✅

### Intelligent Availability Zone Selection

Workflows use intelligent availability zone selection strategy:

1. **Priority use [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor) recommended zones**: Zones corresponding to the optimal instance type returned by the tool
2. **Dynamic query zones supporting the instance type**: Get all zones supporting the instance type through `DescribeAvailableResource` API
3. **Fallback to preset zones**: If dynamic query fails, use preset zone list
   - **ARM64**: `cn-hangzhou-b, cn-hangzhou-j, cn-hangzhou-k`
   - **AMD64**: `cn-hangzhou-b, cn-hangzhou-g, cn-hangzhou-h, cn-hangzhou-i, cn-hangzhou-j, cn-hangzhou-k`

If a zone cannot create instances (insufficient resources, unsupported instance type, etc.), it will automatically try the next zone.

### Verify Availability Zone Support

You can use the following commands to verify instance support in specific zones:

```bash
# Query zones supporting ARM64 instances (example: ecs.c8y.2xlarge)
aliyun ecs DescribeAvailableResource \
  --RegionId cn-hangzhou \
  --DestinationResource InstanceType \
  --InstanceType ecs.c8y.2xlarge \
  --Output table

# Query zones supporting AMD64 instances (example: ecs.c6.xlarge)
aliyun ecs DescribeAvailableResource \
  --RegionId cn-hangzhou \
  --DestinationResource InstanceType \
  --InstanceType ecs.c6.xlarge \
  --Output table
```

## Cost Analysis

### Intelligent Instance Type Selection

Workflows automatically query available instance types and select the **most cost-effective** instance type to ensure maximum cost efficiency.

#### Intelligent Instance Type Selection Strategy

Workflows **use [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor) tool to query spot instance prices in real-time** and **select optimal instances by price per core**.

**Tool Integration**:

- **Real-time Price Query**: Use [`spot-instance-advisor`](https://github.com/maskshell/spot-instance-advisor) to get accurate spot prices
- **Intelligent Filtering**: Automatically filter based on CPU/RAM ratio and architecture
- **Price Sorting**: Select cheapest instance type by price per core
- **Spot Price Limit**: Automatically set to 120% of lowest price

**Supported Instance Families**:

**ARM64 Architecture**:

- `ecs.c8y` - Compute Optimized ARM64 instances (CPU:RAM = 1:2)
- `ecs.c8r` - Compute Optimized ARM64 instances (CPU:RAM = 1:2)

**AMD64 Architecture**:

- No instance family restriction, tool automatically selects optimal instances matching CPU:RAM = 1:1 ratio

#### Tool Usage Examples

```bash
# Query AMD64 instance prices (8c8g to 64c64g, CPU:RAM = 1:1)
# Using spot-instance-advisor: https://github.com/maskshell/spot-instance-advisor
spot-instance-advisor \
  -accessKeyId=xxx \
  -accessKeySecret=xxx \
  -region=cn-hangzhou \
  -mincpu=8 -maxcpu=64 -minmem=8 -maxmem=64 \
  -resolution=7 -limit=20 --json

# Query ARM64 instance prices (8c16g to 64c128g, CPU:RAM = 1:2)
# Using spot-instance-advisor: https://github.com/maskshell/spot-instance-advisor
spot-instance-advisor \
  -accessKeyId=xxx \
  -accessKeySecret=xxx \
  -region=cn-hangzhou \
  -family="ecs.c8y,ecs.c8r" \
  -mincpu=8 -maxcpu=64 -minmem=16 -maxmem=128 \
  -resolution=7 -limit=20 --json
```

**Specification Requirements**:

- **AMD64**: CPU:RAM = 1:1 ratio, 8c8g to 64c64g specification range, no instance family restriction
- **ARM64**: CPU:RAM = 1:2 ratio, 8c16g to 64c128g specification range, limited to `ecs.c8y,ecs.c8r` instance families
- **Dynamic Selection**: Tool automatically queries all eligible instance types and selects optimal instance by price per core
- **No Preset Required**: No need to hardcode specific instance types, completely determined by tool dynamically

#### Price Optimization Strategy

1. **Confirm Instance Family Query**: Query available instance types within confirmed existing instance families
2. **Architecture Intelligent Filtering**: Select corresponding instance families based on ARM64/AMD64 architecture
3. **Price History Analysis**: Get spot price history data from the past 1 hour
4. **Price Sorting Within Instance Family**: Sort instance types by price within the same instance family
5. **Optimal Selection**: Automatically select the lowest-priced instance type
6. **Price Limit Protection**: Set maximum price limit to 120% of lowest price to avoid price fluctuations

#### Selection Logic Example

```text
AMD64 Query Result Example (dynamic query, no instance family restriction):
- ecs.c6.2xlarge: ¥0.15/hour  (8c8g)
- ecs.c6.4xlarge: ¥0.30/hour  (16c16g)
- ecs.c6.8xlarge: ¥0.60/hour  (32c32g)
- ecs.c6.16xlarge: ¥1.20/hour (64c64g)

Auto Selection: ecs.c6.2xlarge (lowest price per core)
Price Limit: ¥0.18/hour (¥0.15 × 1.2)

ARM64 Query Result Example (limited to ecs.c8y,ecs.c8r instance families):
- ecs.c8y.2xlarge: ¥0.24/hour  (8c16g)
- ecs.c8y.4xlarge: ¥0.47/hour  (16c32g)
- ecs.c8y.8xlarge: ¥0.94/hour  (32c64g)
- ecs.c8y.16xlarge: ¥1.88/hour (64c128g)

Auto Selection: ecs.c8y.2xlarge (lowest price per core)
Price Limit: ¥0.29/hour (¥0.24 × 1.2)
```

### Build Time Comparison

| Build Method | Host | Build Time | Cost |
|--------------|------|------------|------|
| **GitHub Runner** | x86_64 | 15-20 minutes | ¥0.2-0.4 |
| **QEMU Emulation** | x86_64 | 50-60 minutes | ¥0.4-0.8 |
| **Native AMD64** | x86_64 | 15-20 minutes | ¥0.1-0.2 |
| **Native ARM64** | ARM64 | 15-20 minutes | ¥0.1-0.2 |
| **On-Demand Spot AMD64** | x86_64 | 15-20 minutes | ¥0.05-0.1 |
| **On-Demand Spot ARM64** | ARM64 | 15-20 minutes | ¥0.05-0.1 |

## Configuration Steps

### 1. Aliyun Resource Preparation

#### Create VPC and VSwitches

```bash
# Create VPC
aliyun vpc CreateVpc \
  --RegionId cn-hangzhou \
  --VpcName openresty-ci-runners \
  --CidrBlock 172.16.0.0/16

# Create VSwitches in multiple availability zones (supporting dynamic zone selection)
# AMD64 zones
aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-b \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.1.0/24 \
  --ZoneId cn-hangzhou-b

aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-g \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.2.0/24 \
  --ZoneId cn-hangzhou-g

aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-h \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.3.0/24 \
  --ZoneId cn-hangzhou-h

aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-i \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.4.0/24 \
  --ZoneId cn-hangzhou-i

aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-j \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.5.0/24 \
  --ZoneId cn-hangzhou-j

aliyun vpc CreateVSwitch \
  --RegionId cn-hangzhou \
  --VSwitchName openresty-ci-switch-k \
  --VpcId vpc-xxx \
  --CidrBlock 172.16.6.0/24 \
  --ZoneId cn-hangzhou-k
```

#### Create Security Group

```bash
# Create security group
aliyun ecs CreateSecurityGroup \
  --RegionId cn-hangzhou \
  --GroupName openresty-ci-sg \
  --VpcId vpc-xxx \
  --Description "Security group for OpenResty runners"

# Add inbound rules
aliyun ecs AuthorizeSecurityGroup \
  --RegionId cn-hangzhou \
  --SecurityGroupId sg-xxx \
  --IpProtocol tcp \
  --PortRange 22/22 \
  --SourceCidrIp 0.0.0.0/0
```

#### Find Images

```bash
# Find AMD64 images
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --Architecture x86_64 \
  --ImageOwnerAlias system \
  --Output table

# Find ARM64 images
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --Architecture arm64 \
  --ImageOwnerAlias system \
  --Output table

# Recommended images (Updated 2024)
# Alibaba Cloud Linux 3 (Recommended - Optimized for Aliyun)
# AMD64: aliyun_3_1903_64_20G_alibase_20241216.vhd
# ARM64: aliyun_3_1903_arm64_20G_alibase_20241216.vhd

# Note: Image IDs may vary by region. Check Aliyun Console for latest versions.
```

#### Image Selection Guide

**Recommended Images (2024):**

**Alibaba Cloud Linux 3** (Recommended)
- Optimized for Aliyun infrastructure
- Better integration with Aliyun services
- Excellent performance for CI/CD workloads
- Uses yum package manager (compatible with workflows)
- Long-term support and regular updates
- Best choice for Aliyun ECS instances

**How to Get Latest Image IDs:**

```bash
# List Alibaba Cloud Linux 3 AMD64 images
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --Architecture x86_64 \
  --ImageOwnerAlias system \
  --ImageName "Alibaba Cloud Linux 3" \
  --Output table

# List Alibaba Cloud Linux 3 ARM64 images
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --Architecture arm64 \
  --ImageOwnerAlias system \
  --ImageName "Alibaba Cloud Linux 3" \
  --Output table

# Alternative: List all Alibaba Cloud Linux images
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --ImageOwnerAlias system \
  --ImageName "Alibaba Cloud Linux" \
  --Output table
```

### 2. GitHub Secrets Configuration

Add the following Secrets in repository settings:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `ALIYUN_ACCESS_KEY_ID` | Aliyun Access Key ID | LTAI5t... |
| `ALIYUN_ACCESS_KEY_SECRET` | Aliyun Access Key Secret | xxx... |
| `ALIYUN_SECURITY_GROUP_ID` | Security Group ID | sg-xxx |
| `ALIYUN_VSWITCH_ID` | Primary VSwitch ID (for fallback) | vsw-xxx |
| `ALIYUN_ARM64_IMAGE_ID` | ARM64 Image ID (Alibaba Cloud Linux 3 recommended) | m-xxx |
| `ALIYUN_AMD64_IMAGE_ID` | AMD64 Image ID (Alibaba Cloud Linux 3 recommended) | m-xxx |
| `ALIYUN_INSTANCE_TYPE` | ARM64 Instance Type | Dynamic Selection* |

**Note**: Since workflows dynamically select availability zones, it's recommended to create VSwitches in multiple zones. `ALIYUN_VSWITCH_ID` is used as fallback, and workflows will prioritize VSwitches corresponding to dynamically queried zones.

### 3. Permission Configuration

#### Aliyun RAM Permission Policies

##### Minimum Permission Policy (Recommended)

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
        "acs:ecs:cn-hangzhou:*:instance/openresty-*-spot-*",
        "acs:ecs:cn-hangzhou:*:image/m-*",
        "acs:ecs:cn-hangzhou:*:securitygroup/sg-*",
        "acs:ecs:cn-hangzhou:*:vswitch/vsw-*"
      ],
      "Condition": {
        "StringLike": {
          "ecs:InstanceName": "openresty-*-spot-*"
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

##### Regional Isolation Policy

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
        "acs:ecs:cn-hangzhou:*:instance/openresty-*-spot-*",
        "acs:ecs:cn-hangzhou:*:image/m-*",
        "acs:ecs:cn-hangzhou:*:securitygroup/sg-*",
        "acs:ecs:cn-hangzhou:*:vswitch/vsw-*"
      ],
      "Condition": {
        "StringEquals": {
          "ecs:RegionId": "cn-hangzhou"
        },
        "StringLike": {
          "ecs:InstanceName": "openresty-*-spot-*"
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
          "ecs:RegionId": "cn-hangzhou"
        }
      }
    }
  ]
}
```

##### VPC Network Isolation Policy

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
        "acs:ecs:cn-hangzhou:*:instance/openresty-*-spot-*",
        "acs:ecs:cn-hangzhou:*:image/m-*",
        "acs:ecs:cn-hangzhou:*:securitygroup/sg-*",
        "acs:ecs:cn-hangzhou:*:vswitch/vsw-*"
      ],
      "Condition": {
        "StringEquals": {
          "ecs:VpcId": "vpc-xxxxxxxxx",
          "ecs:VSwitchId": "vsw-xxxxxxxxx",
          "ecs:RegionId": "cn-hangzhou"
        },
        "StringLike": {
          "ecs:InstanceName": "openresty-*-spot-*"
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
          "ecs:RegionId": "cn-hangzhou"
        }
      }
    }
  ]
}
```

#### GitHub Permissions

- `contents: read` - Read repository content
- `packages: write` - Push images
- `actions: write` - Manage runners

#### Permission Explanations

**Required Aliyun API Permissions**:

| API Permission | Purpose | Workflow Usage |
|----------------|---------|----------------|
| `ecs:RunInstances` | Create spot instances | ✅ All build workflows |
| `ecs:DescribeInstances` | Query instance status | ✅ Cleanup and list operations |
| `ecs:DeleteInstance` | Delete instances | ✅ Cleanup workflows |
| `ecs:DescribeAvailableResource` | Query available resources and zones | ✅ [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor) + dynamic zone query |
| `ecs:DescribeSpotPriceHistory` | Query spot prices | ✅ [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor) |
| `ecs:DescribeImages` | Query image information | ✅ Image validation |
| `ecs:DescribeSecurityGroups` | Query security groups | ✅ Security group validation |
| `ecs:DescribeVSwitches` | Query VSwitches | ✅ Network validation |
| `ecs:DescribeVpcs` | Query VPCs | ✅ Network validation |

**Resource Restrictions**:

- Instance names: `openresty-*-spot-*` (matches actual naming pattern)
- Security groups: `sg-*` (Aliyun security group ID prefix)
- VSwitches: `vsw-*` (Aliyun VSwitch ID prefix, supports multi-zone dynamic selection)
- Images: `m-*` (Aliyun image ID prefix)
- Region restriction: `cn-hangzhou` (production environment)
- Network isolation: Optional VPC and VSwitch restrictions

**Multi-Zone Support Notes**:

- Workflows dynamically query and try multiple zones to create instances
- Permission policies use `vsw-*` wildcard to ensure access to all zone VSwitches
- Recommend pre-creating VSwitches in multiple zones to improve creation success rate

### 4. Security Best Practices

#### Permission Policy Comparison

| Policy Type | Security Level | Use Case | Permission Scope | Risk Level |
|-------------|----------------|----------|------------------|------------|
| **Minimum Permission Policy** | 🔒 High | Production Environment | Limited to specific resources | 🟢 Low |
| **Regional Isolation Policy** | 🔒 High | Multi-region Deployment | Limited to region scope | 🟢 Low |
| **VPC Network Isolation** | 🔒 Highest | Enterprise Level | Complete network isolation | 🟢 Very Low |
| **Original Policy** | ⚠️ Low | Test Environment | Global permissions | 🔴 High |

#### Recommended Implementation Order

1. **Development Phase**: Use minimum permission policy
2. **Testing Phase**: Add regional isolation
3. **Production Phase**: Implement VPC network isolation
4. **Enterprise Level**: Combine time restrictions and IP whitelist

### 5. Security Best Practices

#### Resource Isolation Strategy

1. **Dedicated VPC Network**:

   ```bash
   # Create dedicated VPC (isolated from production environment)
   aliyun vpc CreateVpc \
     --RegionId cn-hangzhou \
     --VpcName openresty-ci-runners \
     --CidrBlock 172.20.0.0/16 \
     --Description "CI/CD runners VPC"
   ```

2. **Dedicated Security Group**:

   ```bash
   # Create minimum permission security group
   aliyun ecs CreateSecurityGroup \
     --RegionId cn-hangzhou \
     --GroupName openresty-ci-sg \
     --VpcId vpc-xxx \
     --Description "CI runners security group"
   
   # Only allow necessary ports
   aliyun ecs AuthorizeSecurityGroup \
     --RegionId cn-hangzhou \
     --SecurityGroupId sg-xxx \
     --IpProtocol tcp \
     --PortRange 22/22 \
     --SourceCidrIp 0.0.0.0/0
   ```

3. **Time Restriction Policy**:

   ```json
   {
     "Version": "1",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ecs:RunInstances",
           "ecs:DeleteInstance"
         ],
         "Resource": "acs:ecs:cn-hangzhou:*:instance/openresty-*-spot-*",
         "Condition": {
           "DateGreaterThan": {
             "acs:CurrentTime": "2024-01-01T00:00:00Z"
           },
           "DateLessThan": {
             "acs:CurrentTime": "2025-12-31T23:59:59Z"
           }
         }
       }
     ]
   }
   ```

4. **IP Whitelist Policy**:

   ```json
   {
     "Version": "1",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ecs:RunInstances",
           "ecs:DeleteInstance"
         ],
         "Resource": "acs:ecs:cn-hangzhou:*:instance/openresty-*-spot-*",
         "Condition": {
           "IpAddress": {
             "acs:SourceIp": [
               "192.168.1.0/24",
               "10.0.0.0/8"
             ]
           }
         }
       }
     ]
   }
   ```

#### Permission Minimization Principles

1. **Remove Unnecessary Permissions**:
   - ❌ `ecs:StartInstance` - Not needed to start instances
   - ❌ `ecs:StopInstance` - Not needed to stop instances  
   - ❌ `ecs:RebootInstance` - Not needed to reboot instances
   - ✅ `ecs:RunInstances` - Create instances
   - ✅ `ecs:DeleteInstance` - Delete instances
   - ✅ `ecs:DescribeInstances` - Query instances

2. **Resource Naming Conventions**:
   - Instance names: `openresty-{arch}-spot-{timestamp}`
   - Security group: `openresty-ci-sg`
   - VSwitch: `openresty-ci-switch-{zone}` (e.g., `openresty-ci-switch-b`)
   - VPC: `openresty-ci-runners`

3. **Regular Permission Auditing**:

   ```bash
   # View Access Key usage
   aliyun ram ListAccessKeys \
     --UserName github-actions
   
   # View permission policies
   aliyun ram ListPoliciesForUser \
     --UserName github-actions
   ```

## Usage

### Automatic Trigger

- Push to `develop`, `master` branches
- Create `v*` tags
- Automatically create spot instances → build → cleanup

### Manual Trigger

#### AMD64 Build

1. Go to Actions page
2. Select "Auto AMD64 Build with Spot Instance"
3. Click "Run workflow"
4. Optionally configure custom tags

#### ARM64 Build

1. Go to Actions page
2. Select "Auto ARM64 Build with Spot Instance"
3. Click "Run workflow"
4. Optionally configure custom tags

### Manual Management

1. Select "Aliyun Spot Runner Manager"
2. Choose operation:
   - `create` - Create instance (supports AMD64/ARM64)
   - `destroy` - Delete instance
   - `list` - List instances
3. Configure parameters:
   - `instance_type` - Instance type (dynamic selection, no preset required)
   - `image_id` - Image ID
   - `runner_name` - Runner name prefix

### Multi-Architecture Image Merge and Release

After AMD64 and ARM64 images are built separately, they can be merged into the same tag without suffix for transparent user pulls. AMD64 images have `-amd64` suffix, ARM64 images have `-arm64` suffix.

#### Using Workflow Merge (Recommended)

Select "Manifest Merge (Multi-Arch)" workflow in Actions page, configure:

- `tag`: Base tag to release (e.g., `v1.0.0`)
- `image_name`: Image name (default `dianplus/openresty`)
- `push_latest`: Whether to also update `:latest`

This workflow will merge the following two images into multi-architecture manifest:

- `ghcr.io/dianplus/openresty:<tag>-amd64` (AMD64 image with architecture suffix)
- `ghcr.io/dianplus/openresty:<tag>-arm64` (ARM64 image with architecture suffix)

And generate:

- `ghcr.io/dianplus/openresty:<tag>` (multi-architecture manifest)
- (Optional) `ghcr.io/dianplus/openresty:latest`

Can also be triggered via command after other workflows complete:

```bash
gh workflow run manifest-merge.yml -f tag="v1.0.0" -f push_latest=true
```

Or via Repository Dispatch:

```bash
gh api repos/:owner/:repo/dispatches \
  -f event_type=merge-manifest \
  -f client_payload='{"tag":"v1.0.0","image_name":"dianplus/openresty","push_latest":true}'
```

#### Pull Example

Users only need to pull the base tag for automatic platform-specific matching:

```bash
docker pull ghcr.io/dianplus/openresty:v1.0.0
```

## Monitoring and Optimization

### Cost Monitoring

```bash
# View AMD64 instance usage
aliyun ecs DescribeInstances \
  --RegionId cn-hangzhou \
  --InstanceName openresty-amd64-spot-* \
  --Output table

# View ARM64 instance usage
aliyun ecs DescribeInstances \
  --RegionId cn-hangzhou \
  --InstanceName openresty-arm64-spot-* \
  --Output table

# View costs
aliyun bss QueryAccountBalance
```

### Performance Optimization

1. **Instance Type Selection**:
   - **AMD64 Standard Build**: 8c8g specification range (dynamic selection)
   - **AMD64 High Performance Build**: 16c16g specification range (dynamic selection)
   - **ARM64 Standard Build**: 8c16g specification range (limited to ecs.c8y,ecs.c8r)
   - **ARM64 High Performance Build**: 16c32g specification range (limited to ecs.c8y,ecs.c8r)

2. **Image Optimization**:
   - Use images with Docker pre-installed
   - Pre-install common build tools

3. **Caching Strategy**:
   - Registry caching
   - Build layer caching
   - AMD64 cache image: `ghcr.io/dianplus/openresty:buildcache-amd64`
   - ARM64 cache image: `ghcr.io/dianplus/openresty:buildcache-arm64`

4. **Parallelism and Native Build**:
   - Default parallelism: `RESTY_J=16` (workflow fixed setting)
   - Recommended mapping: 8/16/32/64 cores → `RESTY_J=8/16/32/64` (starting from actual minimum specification)
   - Platform: Use self-hosted native Runner builds (AMD64: `[self-hosted, AMD64]`, ARM64: `[self-hosted, ARM64]`), avoid QEMU emulation

5. **Observability Recommendations**:
   - Record build time, instance specifications, `RESTY_J` values as baseline for future tuning

### Troubleshooting

#### Common Issues

1. **Instance Creation Failed**
   - Check quota limits
   - Verify image and instance type compatibility
   - Insufficient zone resources: Workflow will intelligently select zones (priority advisor recommendation → dynamic query zones supporting the instance type → preset zone fallback)
   - Spot failure/price fluctuation: Strategy is `SpotAsPriceGo`, price limit = lowest price × 1.2; change specification or retry if necessary

2. **Runner Registration Failed**
   - Check network outbound and DNS
   - Verify `actions: write` and Token permissions
   - View Runner logs: `/home/runner/runner.log`
   - Quick verification: `gh api repos/<owner>/<repo>/actions/runners | jq '.runners[] | {name,status,labels}'`

3. **Build Timeout**
   - Prioritize reducing parallelism (e.g., lower `RESTY_J`)
   - Increase instance specifications (CPU/memory)
   - Confirm cache hits (`cache-from` available) and optimize Dockerfile

4. **Image Push Failed**
   - Confirm `packages: write` permission and GHCR login (`docker/login-action@v3`)
   - Verify image namespace: `ghcr.io/dianplus/openresty`
   - Use `type=sha` derived tags or disable provenance for tag conflicts (e.g., restricted environments)

5. **Insufficient Permissions/Quota Issues**
   - Complete RAM permissions: `ecs:DescribeAvailableResource`, `ecs:DescribeSpotPriceHistory`, etc.
   - Check and increase quotas (CPU, EIP, disk, etc.) according to enterprise console guidance

#### Log Viewing

```bash
# View instance logs
aliyun ecs DescribeInstanceHistoryEvents \
  --InstanceId i-xxx \
  --Output table
```

## Automatic Cleanup Mechanism

### How It Works

Workflows automatically destroy ECS instances after build completion, ensuring:

- **Immediate Cleanup**: Delete instances immediately after build completion
- **Failure Protection**: Use `if: always()` to ensure cleanup even if build fails
- **Cost Control**: Avoid instances running for extended periods generating costs
- **Security Isolation**: Prevent instances from being maliciously exploited

### Cleanup Steps

Workflows implement cleanup through independent `cleanup` job:

```yaml
cleanup:
  needs: [create-spot-runner, build-amd64]
  runs-on: ubuntu-latest
  if: always()
  steps:
    - name: Cleanup Spot Instance
      if: needs.create-spot-runner.outputs.instance_id != ''
      run: |
        echo "Cleaning up instance: ${{ needs.create-spot-runner.outputs.instance_id }}"
        aliyun ecs DeleteInstance --InstanceId ${{ needs.create-spot-runner.outputs.instance_id }} --Force true
        echo "✅ Instance cleaned up successfully"
```

### Key Features

- **`if: always()`**: Execute cleanup regardless of build success or failure
- **`--Force true`**: Force deletion to avoid instance state issues
- **Logging**: Record cleanup process for debugging
- **Unified Cleanup**: Only use workflow cleanup, remove instance internal scheduled tasks to avoid logic conflicts

## CPU-Intensive Build Optimization

### OpenResty Build Characteristics

OpenResty builds are typical **CPU-intensive tasks**, mainly consuming:

- **OpenSSL Compilation**: Encryption algorithms require extensive CPU computation
- **LuaJIT Compilation**: JIT compiler requires extensive CPU resources  
- **Nginx Module Compilation**: Various C module compilation processes
- **Parallel Compilation**: `make -j${RESTY_J}` uses multi-core parallel compilation

### Instance Selection Recommendations

#### AMD64 Architecture (CPU:RAM = 1:1 Ratio)

| Task Type | Specification Range | CPU | Memory | Use Case | Build Time | Cost/Build |
|-----------|-------------------|-----|--------|----------|------------|------------|
| **Standard Build** | 8c8g | 8vCPU | 8GB | **Recommended** | 12-15 minutes | ¥0.1-0.2 |
| **High Performance Build** | 16c16g | 16vCPU | 16GB | Large Projects | 8-12 minutes | ¥0.3-0.6 |
| **Ultra High Performance** | 32c32g | 32vCPU | 32GB | Enterprise | 6-10 minutes | ¥0.6-1.2 |
| **Extreme Performance** | 64c64g | 64vCPU | 64GB | Ultra Large Projects | 4-6 minutes | ¥1.2-2.4 |

*Actual instance types dynamically selected through [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor), sorted by price per core

#### ARM64 Architecture (CPU:RAM = 1:2 Ratio)

| Task Type | Specification Range | CPU | Memory | Use Case | Build Time | Cost/Build |
|-----------|-------------------|-----|--------|----------|------------|------------|
| **Standard Build** | 8c16g | 8vCPU | 16GB | **Recommended** | 10-12 minutes | ¥0.2-0.4 |
| **High Performance Build** | 16c32g | 16vCPU | 32GB | Large Projects | 8-10 minutes | ¥0.4-0.8 |
| **Ultra High Performance** | 32c64g | 32vCPU | 64GB | Enterprise | 6-8 minutes | ¥0.8-1.6 |
| **Extreme Performance** | 64c128g | 64vCPU | 128GB | Ultra Large Projects | 4-6 minutes | ¥1.6-3.2 |

*Limited to ecs.c8y,ecs.c8r instance families, dynamically select optimal instances through [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor)

### High Core Count Instance Benefit Analysis

#### 16-Core Instance Benefits

**Instance Specification**: 16c16g (16vCPU 16GB, AMD64 architecture)

**Performance Improvements**:

- **Build Time**: Reduced from 15-20 minutes to 8-12 minutes
- **Time Savings**: Approximately 40-50% time reduction
- **Parallelism**: `make -j16` fully utilizes 16 cores
- **Cost**: Single build ¥0.3-0.6 (2-3x more expensive than 8 cores)

**Use Cases**:

- Large projects or complex dependencies
- Frequent build development environments
- Production environments sensitive to build time

#### 32-Core Instance Benefits

**Instance Specification**: 32c32g (32vCPU 32GB, AMD64 architecture)

**Performance Improvements**:

- **Build Time**: Reduced from 15-20 minutes to 6-10 minutes
- **Time Savings**: Approximately 50-60% time reduction
- **Parallelism**: `make -j32` fully utilizes 32 cores
- **Cost**: Single build ¥0.6-1.2 (4-6x more expensive than 8 cores)

**Use Cases**:

- Enterprise-level large projects
- Multi-architecture simultaneous builds
- Time-critical scenarios

#### Benefit Assessment

| Core Count | Build Time | Cost/Build | Time Savings | Cost Efficiency | Recommended Use Case |
|------------|------------|------------|--------------|-----------------|---------------------|
| **8 Cores** | 12-15 minutes | ¥0.1-0.2 | Baseline | **Best** | Daily Development |
| **16 Cores** | 8-12 minutes | ¥0.3-0.6 | 40-50% | Good | Frequent Builds |
| **32 Cores** | 6-10 minutes | ¥0.6-1.2 | 50-60% | Fair | Enterprise Level |

### Parallelism Control Mechanism

#### Dockerfile Level

```dockerfile
# Default settings in Dockerfile
ARG RESTY_J="4"  # Optimized from "1" to "4"

# Actual usage locations
&& make -j${RESTY_J} \           # OpenSSL compilation
&& make -j${RESTY_J} install_sw \ # OpenSSL installation
&& CFLAGS="-g -O3" make -j${RESTY_J} \ # PCRE2 compilation
&& make -j${RESTY_J} \           # OpenResty compilation
&& make -j${RESTY_J} install \   # OpenResty installation
```

#### Workflow Level

```yaml
# Dynamic override in workflow
build-args: |
  RESTY_J=16  # Dynamically set based on instance core count
```

#### Parallelism Setting Recommendations

| Instance Core Count | RESTY_J Value | Use Case | Performance Improvement |
|-------------------|---------------|----------|------------------------|
| **8 Cores** | `RESTY_J=8` | Standard Build | Baseline |
| **16 Cores** | `RESTY_J=16` | High Performance Build | 2x Improvement |
| **32 Cores** | `RESTY_J=32` | Ultra High Performance | 4x Improvement |
| **64 Cores** | `RESTY_J=64` | Extreme Performance | 8x Improvement |

### Performance Optimization Recommendations

1. **Select Compute Optimized Instances**: AMD64 no instance family restriction, ARM64 limited to ecs.c8y,ecs.c8r series
2. **Reasonable Parallelism Settings**:
   - **Dockerfile Default**: `ARG RESTY_J="4"` (optimized)
   - **Workflow Override**: Fixed setting `RESTY_J=16` through `build-args`
   - **8 Core Instance**: `RESTY_J=8` (recommended adjustment)
   - **16 Core Instance**: `RESTY_J=16` (workflow default)
   - **32 Core Instance**: `RESTY_J=32` (recommended adjustment)
3. **Specification Ratio Optimization**: AMD64 uses 1:1 ratio, ARM64 uses 1:2 ratio, automatically avoid memory-intensive instances
4. **Monitor Build Time**: Adjust instance specifications based on actual build time
5. **Cost-Benefit Balance**: High core count suitable for frequent builds, standard builds recommend starting from 8 cores

## Best Practices

### 1. Cost Control

- Use spot instances with reasonable price limits
- **Automatic Cleanup Mechanism**: Workflows immediately destroy ECS instances after build completion
- **`if: always()` Ensures Cleanup**: Execute cleanup steps regardless of build success or failure
- **Avoid Long-Running Instances**: Prevent resource waste and cost accumulation
- Monitor usage and optimize instance specifications

### 2. Reliability

- Set up retry mechanisms
- Monitor build status
- Prepare backup solutions

### 3. Security

- Use minimum permission principles
- Regularly rotate Access Keys
- Monitor abnormal access

## Extension Solutions

### Multi-Region Deployment

- Support multiple Aliyun regions
- Select instances by proximity
- Improve availability

### Multi-Cloud Support

- Support Tencent Cloud, Huawei Cloud
- Price comparison selection
- Failover

### Pre-Built Images

- Create base images with common dependencies
- Reduce build time
- Improve success rate
