# OpenResty for DianPlus

## 上游 OpenResty Dockerfile

- 上游参考: `https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile`

## 自动化构建

本项目使用 GitHub Actions 进行自动化构建，支持 AMD64 和 ARM64 架构

### 构建触发器

- **自动触发**: 推送到 `develop`/`master` 分支时，或创建 `v*` 标签时自动触发
- **手动触发**: 通过 GitHub Actions 页面手动运行工作流

### 镜像访问

构建完成后，镜像推送到 GitHub Container Registry：

- **多架构合并镜像**（推荐）: `ghcr.io/dianplus/openresty:<tag>` - Docker 自动匹配平台
- **架构特定镜像**（调试用）: `ghcr.io/dianplus/openresty:<tag>-amd64` 或 `ghcr.io/dianplus/openresty:<tag>-arm64`

### 标签策略

项目采用两阶段标签策略：

- 构建阶段创建架构特定标签（如 `latest-amd64`、`latest-arm64`）
- 合并阶段创建统一标签（如 `latest`）

用户可直接拉取统一标签，Docker 会自动匹配平台。

详细说明请参考 [需求文档 - 标签策略](requirements/02-workflows.md#标签策略说明)。

### 优势

- **原生构建**: AMD64 和 ARM64 都在原生架构实例上构建，无 QEMU 模拟开销
- **超低成本**: 单次构建成本约 ¥0.05-0.1
- **自动清理**: 构建完成后自动销毁 Spot 实例

详细配置请参考 [需求文档](requirements/README.md)。
