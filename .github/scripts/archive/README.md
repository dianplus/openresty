# Archived Scripts

本目录包含已归档的旧版本脚本文件。

## 归档历史

### 2024-12-XX (Python 重构)
- `find-cheapest-instance.sh` - 旧版本的查找最便宜实例脚本
  - 原因：重构为 Python 版本（`find-cheapest-instance.py`），更好的 JSON 处理和错误处理
  - 特点：使用 shell + jq 处理 JSON，逻辑复杂，难以维护
  
- `create-spot-instance.sh` - 旧版本的创建 spot 实例脚本
  - 原因：重构为 Python 版本（`create-spot-instance.py`），更清晰的代码结构
  - 特点：使用 shell heredoc 生成 user_data，错误处理较弱
  
- `wait-instance-ready.sh` - 旧版本的等待实例就绪脚本
  - 原因：重构为 Python 版本（`wait-instance-ready.py`），更简洁的轮询逻辑
  - 特点：使用 shell 循环 + jq 解析状态
  
- `cleanup-instance.sh` - 旧版本的清理实例脚本
  - 原因：重构为 Python 版本（`cleanup-instance.py`），简化逻辑
  - 特点：简单的 shell 脚本，重构为 Python 以保持一致性

## Python 版本的优势

新版本 Python 脚本的主要改进：

1. **更好的 JSON 处理**：使用标准库 `json`，类型安全，无需复杂的 jq 管道
2. **更好的错误处理**：异常处理机制，更易调试
3. **更好的可维护性**：代码结构清晰，类型注解，易于理解
4. **更好的调试体验**：可以直接打印数据结构，无需复杂的 shell 调试
5. **原生跨平台**：Python 在 GitHub Actions 中默认可用

## 如需恢复旧版本

如果需要参考或恢复旧版本，可以从本目录复制回 `.github/scripts/` 目录。

```bash
cp .github/scripts/archive/find-cheapest-instance.sh .github/scripts/
```

## 保留的 Shell 脚本

以下脚本仍然保留为 Shell 版本（简单或特殊用途）：
- `configure-aliyun-cli.sh` - 简单的 CLI 配置
- `setup-runner.sh` - 在 ECS 实例上运行，主要是 Shell 逻辑
- 测试脚本（`test-*.sh`）- 测试工具

