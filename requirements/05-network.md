# 网络要求

主要是网络代理方面的需求描述

## 概述

Runner 实例在配置和注册阶段需要访问 GitHub 服务器（`api.github.com`、`github.com` 等）。

如 Self-hosted runner 实例位于中国内地的网络环境下，则通常需要通过代理服务器才能正常连接。

代理服务器的配置，应在 Runner 注册之前完成。

## 代理配置

### 代理使用范围限制

**重要限制**：为简化环境配置，此处的代理服务器默认为在目标 VPC 内创建的私网代理服务器，仅供 Spot Instance 内部使用，而**不能在 GitHub-Hosted Runner 中使用**：

1. **✅ Spot Instance（Self-Hosted Runner）**：
   - 可以在创建的 Spot Instance 内部使用代理设置
   - 代理配置用于访问 GitHub 服务（`api.github.com`、`github.com` 等）
   - 代理配置必须在 Runner 注册之前完成

2. **❌ GitHub-Hosted Runner**：
   - **禁止**在 GitHub-Hosted Runner 中使用代理设置
   - GitHub-Hosted Runner 直接连接到 GitHub 服务，无需代理
   - 在 GitHub-Hosted Runner 的 workflow 步骤中不应设置或使用代理环境变量

3. **User Data 脚本生成**：
   - 如果脚本需要生成 User Data，应确保将代理配置传递给 User Data 模板
   - 使用模板文件时，通过参数或环境变量传递代理配置
   - 确保生成的 User Data 脚本中代理配置在 Runner 注册（与 Github 通信）之前生效
   - 代理配置仅在 Spot Instance 内部生效

4. **脚本内部处理**：
   - 独立脚本应支持从环境变量读取代理配置（用于传递给 Spot Instance）
   - 对于在 GitHub-Hosted Runner 中执行的脚本，不应设置代理环境变量
   - 对于需要调用外部 API 的脚本（如 Aliyun CLI），确保在 GitHub-Hosted Runner 中不使用代理
   - 确保 `NO_PROXY` 配置正确，避免代理误转发内部服务（如阿里云元数据服务 `100.100.100.200`）

NO_PROXY 示例：

```bash
export NO_PROXY=localhost,127.0.0.1,::1,100.100.100.200,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,mirrors.tuna.tsinghua.edu.cn,mirrors.aliyun.com,.aliyun.com,.aliyuncs.com,.alicdn.com,.dianplus.cn,.dianjia.io,.taobao.com
```

## 阿里云 ECS 配置

### 不需要公网 IP

Self-hosted runner 不需要公网 IP 地址，通过 NAT 网关进行公网通信。
