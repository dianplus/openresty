# Archived Workflows

本目录包含已归档的旧版本 workflow 文件。

## 归档历史

### 2024-10-31
- `auto-amd64-build.yml.old` - 旧版本的 AMD64 构建 workflow
  - 原因：被新的 clean 版本替代，新版本使用分离的脚本文件，更易维护
  - 特点：包含大量内联 shell 脚本，难以维护和调试
  
- `auto-arm64-build.yml.old` - 旧版本的 ARM64 构建 workflow
  - 原因：被新的 clean 版本替代，新版本使用分离的脚本文件，更易维护
  - 特点：包含大量内联 shell 脚本，难以维护和调试

## 新版本改进

新版本 (`auto-amd64-build.yml` 和 `auto-arm64-build.yml`) 的主要改进：

1. **脚本分离**：所有 shell 脚本逻辑提取到 `.github/scripts/` 目录
2. **更好的可维护性**：脚本可以在本地测试，无需提交到 GitHub
3. **统一的错误处理**：所有脚本使用统一的日志和错误处理
4. **代码复用**：脚本可以在多个 workflow 中复用
5. **避免转义问题**：不再需要在 YAML 中处理复杂的 shell 变量转义

## 如需恢复旧版本

如果需要参考或恢复旧版本，可以从本目录复制回 `.github/workflows/` 目录。

```bash
cp .github/workflows/archive/auto-amd64-build.yml.old .github/workflows/auto-amd64-build.yml
```

