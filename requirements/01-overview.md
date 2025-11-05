# 项目概述与架构

## 项目简介

项目使用 GitHub Actions 和阿里云 Spot 竞价实例，实现低成本、高性能的多架构（AMD64/ARM64）容器镜像自动化构建。

根目录的 Dockerfile 及其配套的配置文件等，可视为一个示例，为一个定制化的 OpenResty 镜像，其上游 Dockerfile 为：<https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile>

## 构建架构

### 多架构支持

支持同时构建 AMD64 和 ARM64 架构的容器镜像。AMD64 和 ARM64 的镜像都在各自的原生架构实例上构建，避免 QEMU 模拟带来的性能损失

## 构建流程概述

项目采用两阶段构建流程，分别处理架构特定镜像构建，以及多架构镜像合并

### 阶段1：架构特定镜像构建

1. 触发构建
   - 分支推送：推送到 `develop`/`master` 分支
   - 标签创建：创建 `v*` 版本标签
   - 手动触发工作流

2. 创建 Spot 实例
   - 通过 [spot-instance-advisor](https://github.com/maskshell/spot-instance-advisor) 工具，动态查询价格最优的实例类型
   - 配置 Self-hosted Runner（Ephemeral 模式）

3. 执行构建
   - 在原生架构实例上构建该架构下的容器镜像
   - 推送到 GitHub Container Registry
   - 标签格式：`<tag>-amd64` 或 `<tag>-arm64`

4. 清理实例
   - 实例内部自毁脚本自动删除实例（主要机制）
   - 工作流 cleanup job 作为兜底验证（兜底机制）
   - 避免成本累积

### 阶段2：多架构镜像合并

合并 Manifest：

- 将 AMD64 和 ARM64 镜像合并
- 创建多架构 manifest
- 标签格式：`<tag>`（无架构后缀）
