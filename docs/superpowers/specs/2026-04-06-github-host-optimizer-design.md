# GitHub Host 智能优选工具 - 设计文档

## 1. 概述

Windows PowerShell 自动化工具，实现 GitHub Host 的智能检测、IP 测速优选、多层兜底防护，自动更新系统 hosts 文件。

## 2. 文件结构

```
github-host/
├── GitHub-Host-Optimizer.ps1    # 主脚本（单文件，模块化函数组织）
├── config.json                   # 用户配置文件
├── my-github-hosts.txt           # 主 Host 文件（用户维护）
├── backup-pool.json              # 备用 IP 池缓存（自动生成）
└── 一键运行.bat                   # 管理员启动快捷方式
```

## 3. 配置文件 (config.json)

配置文件缺失时自动创建空模板，提示用户补充：

```json
{
  "mainHostFile": "my-github-hosts.txt",
  "systemHostsPath": "C:\\Windows\\System32\\drivers\\etc\\hosts",
  "backupPoolFile": "backup-pool.json",
  "remoteHostSources": [],
  "thirdPartyDnsApis": [],
  "testTimeoutMs": 1000,
  "retryCount": 1,
  "autoBackup": true
}
```

用户需自行补充：
- `remoteHostSources`：远程备用 Host 源 URL 列表
- `thirdPartyDnsApis`：第三方 IP 查询 API 列表（可选）

### 配置项说明

| 配置项 | 类型 | 说明 |
|--------|------|------|
| mainHostFile | string | 主 Host 文件路径（相对或绝对） |
| systemHostsPath | string | 系统 hosts 文件路径 |
| backupPoolFile | string | 备用 IP 池缓存文件路径 |
| remoteHostSources | array | 远程备用 Host 源 URL 列表 |
| thirdPartyDnsApis | array | 第三方 IP 查询 API 列表（空则跳过该层） |
| testTimeoutMs | int | TCP 测速超时时间（毫秒） |
| retryCount | int | 测速失败重试次数 |
| autoBackup | bool | 是否自动备份系统 hosts |

## 4. 核心流程

### 4.1 主流程

```
1. 检查管理员权限
   ├→ 有权限 → 继续
   └→ 无权限 → 尝试以管理员身份重新运行（UAC 提示）
       ├→ 用户同意 → 以管理员身份重新运行
       └→ 用户拒绝 → 继续无管理员权限模式
2. 加载配置文件（无配置则创建空模板并提示用户补充）
3. 解析主 Host 文件
4. 对每条域名记录执行四层优选流程
5. 汇总结果
6. 更新 my-github-hosts.txt（始终执行）
7. 若有管理员权限 → 写入系统 hosts
   若无管理员权限 → 输出提示"无管理员权限，已更新主 Host 文件，请手动复制到系统 hosts 或以管理员身份重新运行"
8. 输出执行报告
```

### 4.2 四层优选流程

```
┌─────────────────────────────────────────┐
│ 第一层：主 IP 测速                       │
│ ├→ 正常 → 保留原 IP，结束               │
│ └→ 失效 → 进入第二层                    │
├─────────────────────────────────────────┤
│ 第二层：本地备用池优选                   │
│ ├→ 有可用 IP → 替换，结束               │
│ └→ 全失效 → 进入第三层                  │
├─────────────────────────────────────────┤
│ 第三层：更新备用池 + 重试                │
│ ├→ 拉取远程源，合并去重                 │
│ ├→ 有可用 IP → 替换，结束               │
│ └→ 全失效 → 进入第四层                  │
├─────────────────────────────────────────┤
│ 第四层：第三方 API 兜底                  │
│ ├→ 未配置 API → 跳过，保留原 IP         │
│ ├→ 有可用 IP → 替换，结束               │
│ └→ 全失效 → 保留原 IP，输出警告         │
└─────────────────────────────────────────┘
```

### 4.3 备用池更新触发条件

- **被动更新**：仅当主 IP + 本地备用池同域名所有 IP 全失效时触发
- **更新流程**：拉取所有配置的远程源 → 合并去重 → 覆盖写入 `backup-pool.json`

## 5. 系统 Hosts 更新策略

### 5.1 原则

**只更新 GitHub 相关域名，保留其他所有内容不变**

### 5.2 实现逻辑

1. 读取系统 hosts 全部内容
2. 逐行解析，识别域名
3. 匹配 `my-github-hosts.txt` 中的域名
4. 替换匹配行的 IP 部分，保留原格式
5. 不匹配的行原样保留
6. 新域名追加到文件末尾

### 5.3 示例

```
# 更新前（系统 hosts）
127.0.0.1 localhost
192.168.1.1 myserver.local
140.82.112.4 github.com

# 更新后
127.0.0.1 localhost                          # 保留
192.168.1.1 myserver.local                   # 保留
140.82.116.4 github.com                      # 仅更新 IP
```

## 6. IP 测速实现

### 6.1 方法

TCP 443 端口握手测试（非 ICMP ping）

### 6.2 代码逻辑

```powershell
function Test-IPSpeed {
    param($IP, $TimeoutMs)
    
    $tcp = New-Object System.Net.Sockets.TcpClient
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $asyncResult = $tcp.BeginConnect($IP, 443, $null, $null)
        $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)
        
        if ($success) {
            $tcp.EndConnect($asyncResult)
            $stopwatch.Stop()
            return @{ Success = $true; Latency = $stopwatch.ElapsedMilliseconds }
        }
        return @{ Success = $false; Latency = -1 }
    }
    finally {
        $tcp.Close()
    }
}
```

### 6.3 延迟排序

对同一域名的多个可用 IP，按延迟升序排序，取最优（延迟最低）IP。

## 7. 错误处理与兜底

### 7.1 异常场景处理

| 场景 | 处理方式 |
|------|----------|
| 无管理员权限 | 先尝试申请管理员权限（UAC），用户拒绝后仅更新 my-github-hosts.txt，输出提示 |
| 配置文件缺失 | 创建空配置文件模板，提示用户补充远程 hosts 源和第三方查询 API |
| 主 Host 文件缺失 | 自动创建模板文件，提示用户补充 |
| 远程源拉取失败 | 跳过该源，继续其他源 |
| 所有远程源失效 | 沿用旧备用池缓存 |
| 第三方 API 未配置 | 跳过第四层 |
| 所有层级全失效 | 保留原 IP，输出警告 |

### 7.2 安全保障

- 任何异常场景均保留原配置
- 写入前可选备份系统 hosts
- 不删除、不清空关键配置

## 8. 输出格式

### 8.1 实时进度

```
[检测] github.com (140.82.112.4)... 正常 (延迟: 156ms)
[检测] raw.githubusercontent.com (185.199.108.133)... 失效
[备用池] raw.githubusercontent.com: 找到 3 个候选 IP
[测速] 185.199.109.133... 正常 (延迟: 89ms)
[替换] raw.githubusercontent.com: 185.199.108.133 → 185.199.109.133
```

### 8.2 执行报告

```
========== 域名可用性检查 ==========
[正常] github.com (140.82.121.3) - 156ms
[正常] api.github.com (140.82.121.5) - 142ms
[替换] raw.githubusercontent.com (185.199.109.133) - 原 IP 失效
[正常] gist.github.com (140.82.121.4) - 198ms
[失效] github-cloud.s3.amazonaws.com - 无可用 IP
...

========== 执行统计 ==========
检测域名: 38 个
正常: 30 个
已替换: 5 个
失效: 3 个
可用率: 92.1%
备用池更新: 是
系统hosts写入: 成功
==============================
```

## 9. 函数模块划分

| 函数名 | 职责 |
|--------|------|
| `Get-Config` | 加载配置文件 |
| `Read-MainHostFile` | 解析主 Host 文件 |
| `Test-IPSpeed` | TCP 443 端口测速 |
| `Get-BackupPool` | 读取本地备用池缓存 |
| `Update-BackupPool` | 从远程源更新备用池 |
| `Get-IPsFromDnsApi` | 调用第三方 API 获取 IP |
| `Select-BestIP` | 从候选 IP 中选最优 |
| `Update-SystemHosts` | 智能更新系统 hosts |
| `Write-Log` | 输出日志信息 |
| `Invoke-MainProcess` | 主流程控制 |

## 10. 配置文件模板

配置文件缺失时自动创建以下模板：

```json
{
  "mainHostFile": "my-github-hosts.txt",
  "systemHostsPath": "C:\\Windows\\System32\\drivers\\etc\\hosts",
  "backupPoolFile": "backup-pool.json",
  "remoteHostSources": [],
  "thirdPartyDnsApis": [],
  "testTimeoutMs": 1000,
  "retryCount": 1,
  "autoBackup": true
}
```

创建后提示用户：
```
[警告] 配置文件已创建，请补充以下配置项：
  - remoteHostSources: 远程备用 Host 源 URL 列表
  - thirdPartyDnsApis: 第三方 IP 查询 API 列表（可选）
```

## 11. 主 Host 文件格式 (my-github-hosts.txt)

```
# GitHub Hosts - 用户维护
# 格式: IP 域名

140.82.113.26 alive.github.com
140.82.114.25 live.github.com
185.199.109.154 github.githubassets.com
140.82.113.21 central.github.com
185.199.108.133 desktop.githubusercontent.com
185.199.110.133 camo.githubusercontent.com
185.199.111.133 github.map.fastly.net
146.75.121.194 github.global.ssl.fastly.net
140.82.121.4 gist.github.com
185.199.111.153 github.io
140.82.121.3 github.com
192.0.66.2 github.blog
140.82.121.5 api.github.com
185.199.109.133 raw.githubusercontent.com
185.199.110.133 user-images.githubusercontent.com
185.199.110.133 favicons.githubusercontent.com
185.199.111.133 avatars5.githubusercontent.com
185.199.110.133 avatars4.githubusercontent.com
185.199.110.133 avatars3.githubusercontent.com
185.199.108.133 avatars2.githubusercontent.com
185.199.110.133 avatars1.githubusercontent.com
185.199.110.133 avatars0.githubusercontent.com
185.199.109.133 avatars.githubusercontent.com
140.82.121.10 codeload.github.com
3.5.24.249 github-cloud.s3.amazonaws.com
52.217.131.105 github-com.s3.amazonaws.com
16.182.39.25 github-production-release-asset-2e65be.s3.amazonaws.com
16.15.253.166 github-production-user-asset-6210df.s3.amazonaws.com
54.231.204.81 github-production-repository-file-5c1aeb.s3.amazonaws.com
185.199.108.153 githubstatus.com
140.82.113.17 github.community
51.137.3.17 github.dev
140.82.113.21 collector.github.com
13.107.42.16 pipelines.actions.githubusercontent.com
185.199.111.133 media.githubusercontent.com
185.199.110.133 cloud.githubusercontent.com
185.199.110.133 objects.githubusercontent.com
```

## 12. 备用池缓存格式 (backup-pool.json)

```json
{
  "lastUpdated": "2026-04-06T17:00:00",
  "domains": {
    "github.com": ["140.82.112.4", "140.82.112.5", "140.82.116.4"],
    "raw.githubusercontent.com": ["185.199.108.133", "185.199.109.133", "185.199.110.133"]
  }
}
```
