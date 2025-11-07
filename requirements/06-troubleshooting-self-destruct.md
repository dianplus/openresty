# 自毁机制排查指南

## 概述

本文档说明如何在 spot instance 内部排查自毁机制问题。

## 快速排查步骤

### 1. 运行排查脚本

在 spot instance 内部运行排查脚本：

```bash
# 下载排查脚本（如果还没有）
curl -o /tmp/debug-self-destruct.sh https://raw.githubusercontent.com/dianplus/openresty/master/.github/scripts/debug-self-destruct.sh
chmod +x /tmp/debug-self-destruct.sh

# 运行排查脚本
sudo bash /tmp/debug-self-destruct.sh
```

或者直接在实例上运行：

```bash
sudo bash .github/scripts/debug-self-destruct.sh
```

### 2. 手动检查关键组件

#### 2.1 检查自毁脚本

```bash
# 检查脚本是否存在
ls -l /usr/local/bin/self-destruct.sh

# 检查脚本内容
cat /usr/local/bin/self-destruct.sh

# 检查脚本权限
stat /usr/local/bin/self-destruct.sh
```

#### 2.2 检查 post-job hook

```bash
# 检查 post-job hook 脚本
ls -l /opt/actions-runner/post-job-hook.sh

# 检查 .env 文件中的配置
grep ACTIONS_RUNNER_HOOK_POST_JOB /opt/actions-runner/.env

# 检查环境变量
env | grep ACTIONS_RUNNER_HOOK
```

**注意**：GitHub Actions Runner 的 post-job hook 需要在 Runner 启动时通过环境变量配置。如果 Runner 服务已经启动，可能需要重启服务才能生效。

#### 2.3 检查 systemd service

```bash
# 检查 service 文件
cat /etc/systemd/system/self-destruct.service

# 检查 service 状态
systemctl status self-destruct.service

# 检查 service 是否启用
systemctl is-enabled self-destruct.service

# 查看 service 日志
journalctl -u self-destruct.service -n 50
```

#### 2.4 检查日志文件

```bash
# 检查自毁脚本日志
sudo tail -f /var/log/self-destruct.log

# 检查 User Data 日志
sudo tail -f /var/log/user-data.log

# 检查 cloud-init 日志
sudo tail -f /var/log/cloud-init.log

# 检查 Runner 服务日志
journalctl -u actions.runner.*.service -n 50
```

#### 2.5 检查 Aliyun CLI

```bash
# 检查是否安装
which aliyun

# 检查版本
aliyun --version

# 测试连接（不实际删除）
INSTANCE_ID=$(curl -s http://100.100.100.200/latest/meta-data/instance-id)
REGION_ID=$(curl -s http://100.100.100.200/latest/meta-data/region-id)
aliyun ecs DescribeInstances --RegionId "${REGION_ID}" --InstanceIds "[\"${INSTANCE_ID}\"]"
```

#### 2.6 检查实例角色

```bash
# 获取实例 ID
curl -s http://100.100.100.200/latest/meta-data/instance-id

# 获取区域 ID
curl -s http://100.100.100.200/latest/meta-data/region-id

# 获取实例角色名称
curl -s http://100.100.100.200/latest/meta-data/ram/security-credentials/

# 获取临时凭证（如果角色已配置）
RAM_ROLE=$(curl -s http://100.100.100.200/latest/meta-data/ram/security-credentials/)
curl -s http://100.100.100.200/latest/meta-data/ram/security-credentials/${RAM_ROLE}
```

#### 2.7 检查 Runner 服务状态

```bash
# 列出所有 Runner 服务
systemctl list-units --type=service | grep actions.runner

# 检查服务状态
systemctl status actions.runner.*.service

# 查看服务日志
journalctl -u actions.runner.*.service -f
```

### 3. 手动测试自毁脚本

**警告**：以下命令会实际删除实例，请谨慎使用！

```bash
# 测试自毁脚本（会实际删除实例）
sudo bash -x /usr/local/bin/self-destruct.sh

# 或者只测试语法（不会删除）
bash -n /usr/local/bin/self-destruct.sh
```

### 4. 常见问题排查

#### 问题 1: 自毁脚本未执行

**可能原因**：

- Post-job hook 未配置
- Runner 服务未正确启动
- 环境变量未设置

**排查步骤**：

```bash
# 检查 post-job hook 配置
cat /opt/actions-runner/.env | grep ACTIONS_RUNNER_HOOK_POST_JOB

# 检查 Runner 服务状态
systemctl status actions.runner.*.service

# 检查环境变量
systemctl show actions.runner.*.service | grep Environment
```

**解决方案**：

- 确保 post-job hook 脚本存在且可执行
- 确保 .env 文件中配置了 `ACTIONS_RUNNER_HOOK_POST_JOB`
- 重启 Runner 服务：`sudo systemctl restart actions.runner.*.service`

#### 问题 2: Aliyun CLI 未安装

**可能原因**：

- Build job 中的 action 未执行
- Aliyun CLI 安装失败

**排查步骤**：

```bash
# 检查是否安装
which aliyun

# 检查 PATH
echo $PATH

# 检查常见安装位置
ls -l /usr/local/bin/aliyun
ls -l /usr/bin/aliyun
```

**解决方案**：

- 检查 build job 日志，确认 `aliyun/setup-aliyun-cli-action@v1` 是否成功执行
- 手动安装 Aliyun CLI（如果需要）

#### 问题 3: 实例角色未配置

**可能原因**：

- 创建实例时未指定 RamRoleName
- 实例角色名称错误

**排查步骤**：

```bash
# 检查实例角色
curl -s http://100.100.100.200/latest/meta-data/ram/security-credentials/

# 如果返回空，说明未配置实例角色
```

**解决方案**：

- 检查创建实例的脚本，确认 `--RamRoleName` 参数是否正确
- 检查 GitHub Variables 中的 `ALIYUN_ECS_SELF_DESTRUCT_ROLE_NAME` 是否正确

#### 问题 4: 权限不足

**可能原因**：

- 实例角色权限策略不正确
- 权限策略中的标签条件不匹配

**排查步骤**：

```bash
# 测试删除实例（会实际删除）
INSTANCE_ID=$(curl -s http://100.100.100.200/latest/meta-data/instance-id)
REGION_ID=$(curl -s http://100.100.100.200/latest/meta-data/region-id)
aliyun ecs DeleteInstance --RegionId "${REGION_ID}" --InstanceId "${INSTANCE_ID}" --Force true
```

**解决方案**：

- 检查实例角色的权限策略，确保包含 `ecs:DeleteInstance` 权限
- 检查权限策略中的标签条件是否匹配实例标签

#### 问题 5: Post-job hook 未触发

**可能原因**：

- GitHub Actions Runner 版本不支持 post-job hook
- 环境变量配置方式不正确

**排查步骤**：

```bash
# 检查 Runner 版本
/opt/actions-runner/run.sh --version

# 检查 post-job hook 配置
cat /opt/actions-runner/.env | grep ACTIONS_RUNNER_HOOK_POST_JOB

# 检查 Runner 服务环境变量
systemctl show actions.runner.*.service | grep Environment
```

**解决方案**：

- 确保使用支持 post-job hook 的 Runner 版本（2.311.0 及以上）
- 如果 post-job hook 不工作，依赖 systemd service 作为备用机制

### 5. 调试技巧

#### 5.1 启用详细日志

修改自毁脚本，添加更多日志：

```bash
# 编辑自毁脚本
sudo vi /usr/local/bin/self-destruct.sh

# 在脚本开头添加
set -x  # 启用调试模式
```

#### 5.2 手动触发自毁

如果 post-job hook 和 systemd service 都不工作，可以手动触发：

```bash
# 手动执行自毁脚本
sudo /usr/local/bin/self-destruct.sh
```

#### 5.3 检查 Runner 退出原因

```bash
# 查看 Runner 服务日志
journalctl -u actions.runner.*.service -n 100

# 查看 Runner 退出代码
systemctl status actions.runner.*.service | grep "Main PID"
```

### 6. 验证清单

在排查完成后，确认以下项目：

- [ ] 自毁脚本存在且可执行：`/usr/local/bin/self-destruct.sh`
- [ ] Post-job hook 脚本存在：`/opt/actions-runner/post-job-hook.sh`
- [ ] .env 文件中配置了 `ACTIONS_RUNNER_HOOK_POST_JOB`
- [ ] Systemd service 已启用：`self-destruct.service`
- [ ] Aliyun CLI 已安装：`which aliyun`
- [ ] 实例角色已配置：可以获取临时凭证
- [ ] 实例角色有删除权限：可以调用 `ecs:DeleteInstance` API
- [ ] 日志文件可写：`/var/log/self-destruct.log`

### 7. 联系支持

如果以上步骤都无法解决问题，请提供以下信息：

1. 排查脚本的完整输出
2. 自毁脚本日志：`/var/log/self-destruct.log`
3. User Data 日志：`/var/log/user-data.log`
4. Systemd service 日志：`journalctl -u self-destruct.service`
5. Runner 服务日志：`journalctl -u actions.runner.*.service`
6. 实例角色配置信息
7. 权限策略配置
