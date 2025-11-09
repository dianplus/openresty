# 自定义镜像使用指南

## 概述

本指南介绍如何通过镜像名称查找镜像 ID，类似 Docker 的 `ubuntu:latest` 引用方式。

## 镜像命名规则

自定义镜像使用固定名称，便于查找和引用：

- **AMD64**: `github-runner-ubuntu24-amd64-latest`
- **ARM64**: `github-runner-ubuntu24-arm64-latest`

## 通过名称查找镜像 ID

### 使用辅助脚本

使用 `get-image-id-by-name.py` 脚本通过名称查找镜像 ID：

```bash
# 设置环境变量
export ALIYUN_REGION_ID=cn-hangzhou
export IMAGE_NAME=github-runner-ubuntu24-amd64-latest
export ARCH=amd64  # 可选，用于筛选架构

# 运行脚本
python3 .github/scripts/get-image-id-by-name.py

# 输出示例：
# IMAGE_ID=m-xxx1234567890
```

### 在 GitHub Actions 工作流中使用

```yaml
- name: Get Image ID by Name
  id: get-image-id
  env:
    ALIYUN_REGION_ID: ${{ vars.ALIYUN_REGION_ID }}
    IMAGE_NAME: github-runner-ubuntu24-amd64-latest
    ARCH: amd64
  run: |
    OUTPUT=$(python3 .github/scripts/get-image-id-by-name.py)
    
    # 解析输出并设置 GitHub Actions 输出
    while IFS='=' read -r key value; do
      if [[ -n "${key}" && -n "${value}" ]]; then
        echo "${key}=${value}" >> $GITHUB_OUTPUT
      fi
    done <<< "${OUTPUT}"

- name: Create Instance
  env:
    ALIYUN_IMAGE_ID: ${{ steps.get-image-id.outputs.IMAGE_ID }}
  run: |
    # 使用镜像 ID 创建实例
    python3 .github/scripts/create-spot-instance.py
```

### 使用 Aliyun CLI 直接查询

```bash
# 查询镜像 ID
aliyun ecs DescribeImages \
  --RegionId cn-hangzhou \
  --ImageOwnerAlias self \
  --ImageName github-runner-ubuntu24-amd64-latest \
  --Architecture x86_64 \
  --query "Images.Image[0].ImageId" \
  --output text
```

## 镜像版本管理

### 自动清理旧版本

每次构建新镜像时，系统会自动清理旧版本，只保留指定数量的最新版本。

- **默认保留数量**: 1（只保留最新版本）
- **配置方式**: 通过 GitHub Variables 设置 `KEEP_IMAGE_COUNT`
  - `1`: 只保留最新版本（默认）
  - `2`: 保留最新 2 个版本
  - `3`: 保留最新 3 个版本

### 版本标签

镜像包含以下标签，用于版本管理：

- `Latest: true` - 标记为最新版本
- `VersionHash` - 版本哈希（用于版本检查）
- `Architecture` - 架构信息（amd64/arm64）
- `BuildTimestamp` - 构建时间戳

## 使用示例

### 示例 1: 在构建工作流中使用自定义镜像

```yaml
- name: Get Custom Image ID
  id: get-custom-image
  env:
    ALIYUN_REGION_ID: ${{ vars.ALIYUN_REGION_ID }}
    IMAGE_NAME: github-runner-ubuntu24-amd64-latest
    ARCH: amd64
  run: |
    OUTPUT=$(python3 .github/scripts/get-image-id-by-name.py)
    while IFS='=' read -r key value; do
      if [[ -n "${key}" && -n "${value}" ]]; then
        echo "${key}=${value}" >> $GITHUB_OUTPUT
      fi
    done <<< "${OUTPUT}"

- name: Create Instance with Custom Image
  env:
    ALIYUN_IMAGE_ID: ${{ steps.get-custom-image.outputs.IMAGE_ID }}
    # ... 其他环境变量
  run: |
    python3 .github/scripts/create-spot-instance.py
```

### 示例 2: 在本地脚本中使用

```bash
#!/bin/bash

# 设置环境变量
export ALIYUN_REGION_ID=cn-hangzhou
export IMAGE_NAME=github-runner-ubuntu24-amd64-latest
export ARCH=amd64

# 获取镜像 ID
IMAGE_ID=$(python3 .github/scripts/get-image-id-by-name.py | grep "^IMAGE_ID=" | cut -d'=' -f2)

if [[ -z "${IMAGE_ID}" ]]; then
  echo "Error: Failed to get image ID"
  exit 1
fi

echo "Using image: ${IMAGE_ID}"

# 使用镜像 ID 创建实例
aliyun ecs RunInstances \
  --RegionId "${ALIYUN_REGION_ID}" \
  --ImageId "${IMAGE_ID}" \
  --InstanceType ecs.g6.large \
  # ... 其他参数
```

## 注意事项

1. **镜像 ID 是必需的**: 阿里云 ECS 必须使用镜像 ID（ImageId）创建实例，不能直接通过名称引用
2. **镜像名称必须完全匹配**: 查询时镜像名称必须完全匹配（区分大小写）
3. **架构筛选**: 如果指定了 `ARCH` 环境变量，脚本会自动筛选对应架构的镜像
4. **多个镜像**: 如果存在多个同名镜像，脚本会返回最新的一个（按创建时间排序）

## 故障排查

### 镜像未找到

如果脚本返回 "Image not found"，请检查：

1. 镜像名称是否正确（区分大小写）
2. 镜像是否已创建完成（状态为 Available）
3. 区域 ID 是否正确
4. 是否有权限访问该镜像

### 权限问题

确保使用的 AccessKey 具有以下权限：

- `ecs:DescribeImages` - 查询镜像信息
- `ecs:RunInstances` - 使用镜像创建实例

