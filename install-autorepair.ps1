# install-autorepair.ps1 — 注册 Windows 计划任务，自动巡检并修复 DSH explorer bug
#
# 默认：登录时运行一次（通过 wscript 隐藏启动，完全无窗口）。
#   -Every30Min ：每 30 分钟巡检一次（同样隐藏启动，无窗口）
#   -Remove     ：删除任务
#   -TaskName   ：任务名（默认 DshExplorerFixAutoRepair）
#
# 无窗口原理：wscript.exe 是 GUI 宿主，它用 WScript.Shell.Run(cmd, 0, True)
# 启动 powershell 时由 OS 直接创建隐藏窗口；而 "powershell.exe -WindowStyle Hidden"
# 仍会先让 conhost 创建控制台窗口再隐藏，所以会闪一下。
#
# 说明：部分受限终端（如沙箱/非交互上下文）里 schtasks 创建“登录时”触发会报
# Access denied；此时会明确提示并回退为“每 30 分钟”计划（功能等价、同样无窗口）。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-autorepair.ps1
#   powershell ... -File install-autorepair.ps1 -Every30Min
#   powershell ... -File install-autorepair.ps1 -Remove
param(
  [switch]$Remove,
  [switch]$Every30Min,
  [string]$TaskName = 'DshExplorerFixAutoRepair'
)

$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$vbs = Join-Path $tools 'dsh-patch-launch.vbs'
$patch = Join-Path $tools 'dsh-patch.ps1'

if ($Remove) {
  schtasks /Delete /TN $TaskName /F 2>$null | Out-Null
  Write-Host "已删除计划任务: $TaskName"
  exit 0
}
if (-not (Test-Path $patch)) { throw "dsh-patch.ps1 not found: $patch" }
if (-not (Test-Path $vbs)) { throw "dsh-patch-launch.vbs not found: $vbs" }

$tr = 'wscript.exe "' + $vbs + '"'

if ($Every30Min) {
  & schtasks.exe /Create /TN $TaskName /TR $tr /SC MINUTE /MO 30 /F
  if ($LASTEXITCODE -ne 0) { throw "schtasks /Create 失败（退出码 $LASTEXITCODE）" }
  Write-Host "已注册计划任务: $TaskName（每 30 分钟巡检，隐藏无窗口）" -ForegroundColor Green
  exit 0
}

& schtasks.exe /Create /TN $TaskName /TR $tr /SC ONLOGON /F
if ($LASTEXITCODE -eq 0) {
  Write-Host "已注册计划任务: $TaskName（登录时运行一次，隐藏无窗口）" -ForegroundColor Green
  exit 0
}

Write-Host "schtasks 创建“登录时”任务被拒（可能是受限终端/沙箱）。" -ForegroundColor Yellow
Write-Host "已回退为“每 30 分钟”计划（同样隐藏、无窗口）：" -ForegroundColor Yellow
& schtasks.exe /Create /TN $TaskName /TR $tr /SC MINUTE /MO 30 /F
if ($LASTEXITCODE -ne 0) { throw "schtasks 回退创建也失败（退出码 $LASTEXITCODE）。请在普通用户终端中重试。" }
Write-Host "已注册计划任务: $TaskName（每 30 分钟巡检，隐藏无窗口）" -ForegroundColor Green
Write-Host "提示：如需“登录时一次”，请在普通（非沙箱）用户终端里重新运行本脚本。" -ForegroundColor Yellow
