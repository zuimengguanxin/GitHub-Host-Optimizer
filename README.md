# GitHub Host Optimizer

> 智能 GitHub Host 优化工具 - 自动测速优选 IP，多层兜底防护，一键优化访问速度

## 简介

GitHub Host Optimizer 是一款专为 Windows 系统设计的自动化工具，通过智能测速和多层兜底机制，自动优化 GitHub 相关域名的 Hosts 配置，解决国内访问 GitHub 速度慢、连接不稳定的问题。

## 核心特性

- **智能测速优选**：基于 TCP 443 端口精准测速，自动选择延迟最低的 IP
- **多层兜底防护**：主 Host → 本地备用池 → 远程备用源 → 第三方 DNS API，四层保障
- **被动更新机制**：仅检测到主 IP 失效时才更新备用池，减少无效网络请求
- **全配置化管理**：支持自定义备用源、DNS API、测速参数等
- **安全可靠**：自动备份系统 hosts，任何异常场景均保留原配置

## 运行环境

- 操作系统：Windows 10/11
- 运行环境：PowerShell 5.1 及以上
- 权限要求：管理员权限（用于修改系统 hosts 文件）

## 快速开始

### 1. 下载项目

```bash
git clone https://github.com/zuimengguanxin/GitHub-Host-Optimizer.git
cd GitHub-Host-Optimizer
```

### 2. 配置 Hosts（可选）

编辑 `my-github-hosts.txt` 文件，添加需要优化的 GitHub 域名：

```
140.82.121.3 github.com
185.199.108.153 assets-cdn.github.com
140.82.112.5 api.github.com
```

### 3. 运行工具

**方式一：双击运行**
- 直接双击 `一键运行.bat` 文件（会自动请求管理员权限）

**方式二：PowerShell 运行**
```powershell
# 右键以管理员身份运行 PowerShell
.\GitHub-Host-Optimizer.ps1
```

## 工作流程

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

## 配置说明

编辑 `config.json` 文件可自定义以下参数：

```json
{
  "mainHostFile": "my-github-hosts.txt",           // 主 Host 文件路径
  "systemHostsPath": "C:\\Windows\\System32\\drivers\\etc\\hosts",  // 系统 hosts 路径
  "backupPoolFile": "backup-pool.json",            // 备用池缓存文件
  "remoteHostSources": [                           // 远程备用 Host 源
    "https://raw.hellogithub.com/hosts",
    "https://raw.githubusercontent.com/maxiaof/github-hosts/refs/heads/master/hosts",
    "https://gitee.com/if-the-wind/github-hosts/raw/main/hosts",
    "https://hosts.gitcdn.top/hosts.txt"
  ],
  "testTimeoutMs": 1000,                           // 测速超时时间（毫秒）
  "retryCount": 2,                                 // 主 IP 测速重试次数
  "remoteSourceRetryCount": 2,                     // 远程备用源重试次数
  "apiRetryCount": 3,                              // DNS API 重试次数
  "autoBackup": true                               // 自动备份系统 hosts
}
```

### 添加远程备用源

在 `remoteHostSources` 数组中添加可靠的 GitHub Host 源：

```json
"remoteHostSources": [
  "https://raw.hellogithub.com/hosts",
  "https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts",
  "https://gitee.com/if-the-wind/github-hosts/raw/main/hosts",
  "https://hosts.gitcdn.top/hosts.txt"
]
```

## 文件说明

- `GitHub-Host-Optimizer.ps1` - 主程序脚本
- `config.json` - 配置文件
- `my-github-hosts.txt` - 主 Host 配置（用户维护）
- `backup-pool.json` - 备用池缓存（自动生成）
- `hosts-backup/` - 系统 hosts 备份目录
- `一键运行.bat` - 快捷启动脚本

## 常见问题

### Q: 为什么需要管理员权限？

A: 修改系统 hosts 文件（`C:\Windows\System32\drivers\etc\hosts`）需要管理员权限。如果没有管理员权限，工具仍会运行，但只更新本地 `my-github-hosts.txt`，不修改系统 hosts。

### Q: 备用池什么时候更新？

A: 备用池采用被动更新机制，只有当主 IP 和本地备用池中的同域名 IP 全部失效时，才会触发远程备用池更新。

### Q: 工具会破坏原有 hosts 配置吗？

A: 不会。工具会保留系统 hosts 文件中的原有内容，仅替换 GitHub 相关域名的 IP 记录，并在修改前自动备份原文件。

### Q: 如何查看运行日志？

A: 工具运行时会实时输出检测结果和优化状态，包括：
- 每个域名的测试结果（OK/REPL/FAIL）
- 选中 IP 的延迟
- 备用池更新状态
- 失败域名列表

### Q: 测速失败怎么办？

A: 工具内置四层兜底机制，如果所有层都失效，会保留原 IP 不做修改，并输出警告信息。您可以：
1. 检查网络连接
2. 更新 `config.json` 中的备用源
3. 手动添加可靠的第三方 DNS API

## 性能说明

- **检测效率**：单次运行通常在 10-15 秒内完成
- **网络占用**：日常运行仅测速本地 IP，仅在检测到故障时才访问网络
- **系统影响**：轻量级设计，对系统性能几乎无影响

## 注意事项

1. **防火墙设置**：确保防火墙允许 PowerShell 访问网络（端口 443）
2. **杀毒软件**：某些杀毒软件可能拦截 hosts 文件修改，需要添加信任
3. **网络环境**：建议在网络稳定时运行，避免在网络波动期间执行
4. **备份还原**：如遇问题，可从 `hosts-backup/` 目录还原系统 hosts

## 贡献指南

欢迎提交 Issue 和 Pull Request！

- 报告 Bug
- 提出新功能建议
- 改进文档
- 提供可靠的备用源

## 许可证

MIT License

## 致谢

感谢以下开源项目提供的 Host 源：
- [GitHub520](https://github.com/521xueweihan/GitHub520)
- [maxiaof/github-hosts](https://github.com/maxiaof/github-hosts)
- [Hellogithub Hosts](https://raw.hellogithub.com/hosts)
- [if-the-wind/github-hosts](https://gitee.com/if-the-wind/github-hosts)

---

**注意**：本工具仅用于优化国内访问 GitHub 的网络体验，请勿用于非法用途。