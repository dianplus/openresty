# Runner 配置

## 概述

GitHub Actions Self-hosted Runner 配置的相关信息

## 凭据类型和用途

### 1. Registration Token（注册令牌）

**用途**: 用于将 self-hosted runner 注册到 GitHub 仓库或组织

**特点**:

- **临时性**: 通常有效期约 1 小时
- **一次性**: 每次注册 runner 时都需要新的 token
- **安全性**: 不能用于其他 GitHub API 操作

**获取方式**:

- 通过 GitHub API: `POST /repos/{owner}/{repo}/actions/runners/registration-token`
- 需要具有 `repo` 权限的 token

### 2. GITHUB_TOKEN（工作流自动生成）

**用途**: GitHub Actions 工作流运行时的自动生成 token

**特点**:

- **自动生成**: 每次工作流运行时 GitHub 自动创建
- **临时性**: 仅在当前工作流运行期间有效
- **权限**: 默认具有 `actions:write` 和 `contents:read` 权限

**使用场景**:

- 获取 registration token（需要 `actions:write` 权限）
- 调用 GitHub API 查询 runner 状态 id
- 工作流内的其他 GitHub API 操作

**限制**:

- **不能直接用于 runner 注册**: `config.sh` 不接受普通的 `GITHUB_TOKEN`
- **需要 registration token**: 必须通过 API 获取 registration token

## Ephemeral Runner 模式

项目使用 **Ephemeral Runner（临时 Runner）模式**，确保每次 Job 都在全新的环境中运行，并在完成后自动清理。
