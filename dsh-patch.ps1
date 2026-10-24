# dsh-patch.ps1 — 就地修复所有 DSH 部署里的 explorer 行为 bug
#
# 修复两项（幂等、带备份、可重复运行）：
#   1) runNativeCommand 对所有子进程设 windowsHide: true → explorer 窗口被抑制
#   2) revealNativePath 用 file:/// URI 作为 /select, 参数 → Win11 上不选中文件
#      改为普通 Windows 路径，保留两参数形式 ["/select,", 路径]（实测对带空格/逗号
#      的路径也可靠；单参数形式对空格路径无效）
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-patch.ps1
#   powershell ... -File dsh-patch.ps1 -Check   # 只检查，有未修复则退出码 2
param([switch]$Check)

$ErrorActionPreference = 'Continue'
$HideOld = 'windowsHide: true'
$HideNew = @'
// explorer.exe is a GUI app: CREATE_NO_WINDOW (windowsHide) suppresses its
		// window while it still exits 1, so the reveal would silently fail. Keep
		// console tools hidden, but let Explorer show its window.
		windowsHide: !/^explorer(?:\.exe)?$/i.test(command)
'@.TrimStart()

# 普通路径（两参数形式，run 调用保持原样）
$UriOld  = 'const target = pathToFileURL(windowsPath, { windows: true }).href.replaceAll(",", "%2C");'
$UriNew  = 'const target = windowsPath;'
# 兼容曾出现过的单参数中间态，回退为两参数形式
$MidUriOld = 'const target = "/select," + windowsPath;'
$MidUriNew = 'const target = windowsPath;'
$MidRunOld = 'await run("explorer.exe", [target], signal);'
$MidRunNew = 'await run("explorer.exe", ["/select,", target], signal);'

$candidates = @()
$globs = @(
  (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx\*\node_modules\@deepseek-ai\dsh-native-command\lib\index.js'),
  (Join-Path $env:APPDATA 'npm\node_modules\@deepseek-ai\dsh-native-command\lib\index.js'),
  (Join-Path $env:ProgramFiles 'nodejs\node_modules\@deepseek-ai\dsh-native-command\lib\index.js')
)
foreach ($g in $globs) { $candidates += @(Get-ChildItem -Path $g -ErrorAction SilentlyContinue) }

if ($candidates.Count -eq 0) {
  Write-Host 'dsh-patch: 未找到任何 DSH 部署的 dsh-native-command（无需处理）'
  exit 0
}

$unpatched = 0
$fixed = 0
foreach ($file in $candidates) {
  $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
  $todo = 0
  foreach ($old in @($HideOld, $UriOld, $MidUriOld, $MidRunOld)) { if ($text.Contains($old)) { $todo++ } }

  if ($todo -eq 0) {
    Write-Host "已修复: $($file.FullName)"
    continue
  }
  if ($Check) {
    Write-Host "需要修复: $($file.FullName)（$todo 项）" -ForegroundColor Yellow
    $unpatched++
    continue
  }
  $backup = "$($file.FullName).dshwhale-fix.bak"
  if (-not (Test-Path $backup)) { Copy-Item -Path $file.FullName -Destination $backup -Force }
  $newText = $text
  if ($newText.Contains($HideOld))  { $newText = $newText.Replace($HideOld, $HideNew) }
  if ($newText.Contains($UriOld))   { $newText = $newText.Replace($UriOld, $UriNew) }
  if ($newText.Contains($MidUriOld)) { $newText = $newText.Replace($MidUriOld, $MidUriNew) }
  if ($newText.Contains($MidRunOld)) { $newText = $newText.Replace($MidRunOld, $MidRunNew) }
  [System.IO.File]::WriteAllText($file.FullName, $newText, [System.Text.UTF8Encoding]::new($false))
  Write-Host "已修复: $($file.FullName)（$todo 项）" -ForegroundColor Green
  $fixed++
}

if ($Check) {
  if ($unpatched -gt 0) { Write-Host "dsh-patch: $unpatched 个文件待修复"; exit 2 }
  Write-Host 'dsh-patch: 全部已修复'
  exit 0
}
Write-Host "dsh-patch: 完成（新修复 $fixed 个）"
exit 0
