# OpenResty for DianPlus

## 上游 OpenResty Dockerfile

- 上游参考: `https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile`

## 自动化构建

本项目使用 GitHub Actions 进行自动化构建，支持 AMD64 和 ARM64 架构

### 构建工作流

项目提供三个主要工作流：

1. **Build AMD64** (`build-amd64.yml`): 在 AMD64 Spot 实例上构建 AMD64 架构镜像
2. **Build ARM64** (`build-arm64.yml`): 在 ARM64 Spot 实例上构建 ARM64 架构镜像
3. **Merge Multi-Arch Manifests** (`merge-manifests.yml`): 合并 AMD64 和 ARM64 镜像为多架构 manifest

### 构建流程

#### 阶段 1: 架构特定镜像构建

1. **触发构建**:
   - 推送到 `develop`/`master` 分支时自动触发（当前已禁用，仅支持手动触发）
   - 创建 `v*` 版本标签时自动触发（当前已禁用，仅支持手动触发）
   - 通过 GitHub Actions 页面手动运行工作流

2. **执行构建**:
   - AMD64 和 ARM64 构建工作流独立运行
   - 每个工作流在对应的原生架构 Spot 实例上构建
   - 构建完成后推送架构特定标签（如 `latest-amd64`、`latest-arm64`）

#### 阶段 2: 多架构镜像合并

1. **触发合并**:
   - 在 AMD64 和 ARM64 构建都完成后，手动触发 `Merge Multi-Arch Manifests` 工作流
   - 输入要合并的标签（不含架构后缀，如 `latest` 或 `v1.0.0`）

2. **执行合并**:
   - 检查对应的架构特定镜像是否存在（`<tag>-amd64` 和 `<tag>-arm64`）
   - 创建并推送多架构 manifest（`<tag>`）
   - Docker 会根据运行平台自动选择对应的架构镜像

### 镜像访问

构建完成后，镜像推送到 GitHub Container Registry：

- **多架构合并镜像**（推荐）: `ghcr.io/dianplus/openresty:<tag>` - Docker 自动匹配平台
- **架构特定镜像**（调试用）: `ghcr.io/dianplus/openresty:<tag>-amd64` 或 `ghcr.io/dianplus/openresty:<tag>-arm64`

### 标签策略

项目采用两阶段标签策略：

- **构建阶段**: 创建架构特定标签（如 `latest-amd64`、`latest-arm64`）
- **合并阶段**: 创建统一标签（如 `latest`）

用户可直接拉取统一标签，Docker 会自动匹配平台。

详细说明请参考 [需求文档 - 标签策略](requirements/02-workflows.md#标签策略说明)。

### 使用示例

#### 构建架构特定镜像

1. 手动触发 `Build AMD64` 工作流
2. 手动触发 `Build ARM64` 工作流
3. 等待两个构建都完成

#### 合并多架构镜像

1. 在 GitHub Actions 页面找到 `Merge Multi-Arch Manifests` 工作流
2. 点击 "Run workflow"
3. 输入要合并的标签（如 `latest` 或 `v1.0.0`）
4. 点击 "Run workflow" 执行合并

#### 拉取镜像

```bash
# 拉取多架构镜像（推荐，Docker 自动匹配平台）
docker pull ghcr.io/dianplus/openresty:latest

# 拉取特定架构镜像（调试用）
docker pull ghcr.io/dianplus/openresty:latest-amd64
docker pull ghcr.io/dianplus/openresty:latest-arm64
```

### 优势

- **原生构建**: AMD64 和 ARM64 都在原生架构实例上构建，无 QEMU 模拟开销
- **超低成本**: 单次构建成本约 ¥0.05-0.1
- **自动清理**: 构建完成后自动销毁 Spot 实例
- **灵活合并**: 支持按需合并多架构镜像，避免不必要的合并操作

详细配置请参考 [需求文档](requirements/README.md)。
