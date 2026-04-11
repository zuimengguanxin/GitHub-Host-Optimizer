# GitHub Host Optimizer - AGENTS.md

## 项目概述

GitHub Host Optimizer 是一款专为 Windows 系统设计的自动化工具，通过智能测速和多层兜底机制，自动优化 GitHub 相关域名的 Hosts 配置，解决国内访问 GitHub 速度慢、连接不稳定的问题。

## 项目类型

**PowerShell 脚本项目** - 无需编译，直接运行 PowerShell 脚本即可。

## 目录结构

```
GitHub-Host-Optimizer/
├── GitHub-Host-Optimizer.ps1    # 主程序脚本入口
├── config.json                   # 配置文件
├── my-github-hosts.txt           # 主 Host 配置（用户维护）
├── backup-pool.json              # 备用池缓存（自动生成）
├── 一键运行.bat                   # 快捷启动脚本
├── hosts-backup/                 # 系统 hosts 备份目录
├── modules/                      # 功能模块目录
│   ├── Admin.ps1                 # 管理员权限管理
│   ├── BackupPool.ps1            # 本地备用池管理
│   ├── Config.ps1                # 配置加载模块
│   ├── DnsApi.ps1                # DNS API 集成
│   ├── HostsFile.ps1             # Hosts 文件操作
│   ├── IPTest.ps1                # IP 测速模块
│   ├── Optimizer.ps1             # 核心优化逻辑
│   └── Report.ps1                # 执行报告输出
├── openspec/                     # 实验性功能目录（git 忽略）
└── docs/                         # 文档目录
```

## 运行方式

### 方式一：双击运行
直接双击 `一键运行.bat` 文件（会自动请求管理员权限）

### 方式二：PowerShell 运行
```powershell
# 右键以管理员身份运行 PowerShell
.\GitHub-Host-Optimizer.ps1
```

### 前置要求
- 操作系统：Windows 10/11
- 运行环境：PowerShell 5.1 及以上
- 权限要求：管理员权限（用于修改系统 hosts 文件）

## 核心工作流程

工具按以下四层优先级处理每个域名：

```
第一层：主 IP 测速
  ↓ (失效)
第二层：本地备用池优选
  ↓ (无可用 IP)
第三层：更新备用池 + 重测
  ↓ (仍无可用 IP)
第四层：第三方 DNS API 兜底
  ↓ (全层失效)
保留原 IP，输出警告
```

## 配置文件说明 (config.json)

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| mainHostFile | 主 Host 文件路径 | my-github-hosts.txt |
| systemHostsPath | 系统 hosts 路径 | C:\Windows\System32\drivers\etc\hosts |
| backupPoolFile | 备用池缓存文件 | backup-pool.json |
| remoteHostSources | 远程备用 Host 源列表 | 5个源 |
| testTimeoutMs | 测速超时时间（毫秒） | 1000 |
| retryCount | 主 IP 测速重试次数 | 2 |
| remoteSourceRetryCount | 远程备用源重试次数 | 2 |
| apiRetryCount | DNS API 重试次数 | 3 |
| autoBackup | 自动备份系统 hosts | true |

## 模块架构

### 主入口 (GitHub-Host-Optimizer.ps1)
- 加载所有模块
- 协调各模块执行流程
- 维护全局统计信息

### 模块职责

| 模块 | 功能 |
|------|------|
| Admin.ps1 | 检测并请求管理员权限 |
| Config.ps1 | 加载和解析 config.json |
| IPTest.ps1 | TCP 443 端口测速 |
| HostsFile.ps1 | 读取/更新 hosts 文件 |
| BackupPool.ps1 | 管理本地备用池缓存 |
| DnsApi.ps1 | 调用第三方 DNS API 获取 IP |
| Optimizer.ps1 | 核心优化决策逻辑（四层兜底） |
| Report.ps1 | 生成执行报告和输出 |

## 开发说明

### 无需构建
这是一个纯 PowerShell 脚本项目，无需任何构建步骤。修改代码后直接运行脚本即可生效。

### 代码规范
- 使用 PowerShell 5.1 兼容语法
- 函数命名使用 PascalCase (如 `Invoke-MainProcess`)
- 模块使用点号 (`.`) 方式加载
- 使用 `param()` 定义函数参数

### 测试方式
直接运行脚本进行测试：
```powershell
.\GitHub-Host-Optimizer.ps1
```

### 注意事项
1. 修改 hosts 文件需要管理员权限
2. 某些杀毒软件可能拦截 hosts 文件修改
3. 测速依赖网络连接（端口 443）

## 关键文件说明

| 文件 | 用途 |
|------|------|
| my-github-hosts.txt | 用户维护的 GitHub 域名和 IP 列表 |
| backup-pool.json | 自动缓存的备用 IP 池 |
| hosts-backup/ | 每次修改前的系统 hosts 备份 |
| config.json | 工具行为配置 |

## 常见问题排查

- **无法获取管理员权限**：以管理员身份运行 PowerShell
- **测速超时**：检查网络连接或调整 `testTimeoutMs` 参数
- **备用池更新失败**：检查 `remoteHostSources` 是否可用
