# GitHub Workflows

## Docker Build Workflow

### 自动触发

- **develop 分支推送**：自动构建并推送到 `ghcr.io/dianplus/openresty:develop`
- **标签策略**：
  - `develop` 分支 → `ghcr.io/dianplus/openresty:develop`
  - commit hash → `ghcr.io/dianplus/openresty:develop-<sha>`

### 手工触发

1. 进入 GitHub Actions 页面
2. 选择 "Docker Build" workflow
3. 点击 "Run workflow"
4. 配置参数：
   - **image_tag**：自定义镜像标签（可选，默认使用分支名）
   - **push_image**：是否推送到注册表（默认：true）

### 使用示例

#### 测试构建（不推送）
```
image_tag: test-build
push_image: false
```

#### 发布自定义版本
```
image_tag: v1.0.0-custom
push_image: true
```

### 镜像访问

构建完成后，镜像将推送到 GitHub Container Registry：
- 地址：`ghcr.io/dianplus/openresty`
- 标签：根据触发方式确定

### 权限要求

- `contents: read`：读取仓库内容
- `packages: write`：推送镜像到 GitHub Container Registry

使用 GitHub Token 自动认证，无需额外配置。
