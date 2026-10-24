# dsh-start.ps1 — DSH 启动器（自带 explorer 修复双保险）
#
# 启动顺序：
#   1) materialize 目标版本到 npx 缓存（不启动服务）
#   2) dsh-patch.ps1 就地修复所有部署的 dsh-native-command
#   3) 设置 NODE_OPTIONS 预加载运行时垫片 dsh-explorer-fix.cjs（版本无关）
#   4) 用 npx 启动 dsh web
#
# 用法：
#   .\dsh-start.cmd                       # 启动最新版
#   .\dsh-start.cmd -Version 0.1.5-rc.2    # 启动指定版本
#   .\dsh-start.cmd -NoShim                # 不加载垫片（仅靠磁盘补丁）
param(
  [string]$Version = '',
  [switch]$NoShim
)

$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot
$spec = if ($Version) { "@deepseek-ai/dsh@$Version" } else { '@deepseek-ai/dsh' }
Write-Host "dsh-start: $spec" -ForegroundColor Cyan

# 1) 确保目标版本在 npx 缓存中存在（只跑 --version，不启动服务）
& npx --yes $spec --version | Out-Null

# 2) 就地修复所有已存在的部署（含刚下载出来的）
& "$tools\dsh-patch.ps1"

# 3) 版本无关的运行时垫片（预加载，早于 DSH 模块）
if (-not $NoShim) {
  $env:NODE_OPTIONS = "--require=$tools\dsh-explorer-fix.cjs"
  Write-Host "dsh-start: 已启用 explorer 修复垫片" -ForegroundColor Green
}

# 4) 启动
& npx --yes $spec web
