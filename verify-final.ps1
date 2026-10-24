param([string]$Target)
# verify-final.ps1 — 自检：用真实模块和预加载垫片各测一次「打开 + 选中」
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File verify-final.ps1 [-Target <file>]
$ErrorActionPreference = 'Continue'

if (-not $Target) {
  $Target = Join-Path $env:TEMP ("dsh-explorer-fix-selftest-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  Set-Content -Path $Target -Value 'selftest' -Encoding UTF8
}
$Target = (Resolve-Path -LiteralPath $Target -ErrorAction Stop).Path

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class DshFixWinChk {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  public static List<long> CabinetHandles() {
    var list = new List<long>();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      var cls = new StringBuilder(256); GetClassName(h, cls, 256);
      if (cls.ToString() == "CabinetWClass") list.Add(h.ToInt64());
      return true;
    }, IntPtr.Zero);
    return list;
  }
  public static void CloseHandle(long h) { SendMessage(new IntPtr(h), 0x0010, IntPtr.Zero, IntPtr.Zero); }
}
"@

function SnapShell {
  $shell = New-Object -ComObject Shell.Application
  $list = @()
  foreach ($w in $shell.Windows()) {
    try {
      $h = [long]$w.HWND
      if ($h -eq 0) { continue }
      $focused = $null
      try { if ($w.Document -and $w.Document.FocusedItem) { $focused = $w.Document.FocusedItem.Path } } catch {}
      $list += [PSCustomObject]@{ HWND = $h; Focused = $focused }
    } catch {}
  }
  $list
}

$script:failed = 0
function Check([string]$label, [string[]]$argv) {
  $pre = @([DshFixWinChk]::CabinetHandles())
  Write-Host "--- $label ---"
  & node @argv
  Start-Sleep -Seconds 4
  $post = @([DshFixWinChk]::CabinetHandles())
  $new = @($post | Where-Object { $pre -notcontains $_ })
  $snap = @(SnapShell)
  $hit = $false
  foreach ($n in $new) { ($snap | Where-Object { $_.HWND -eq $n }) | ForEach-Object { if ($_.Focused -eq $Target) { $hit = $true } } }
  if ($hit) { Write-Host "  PASS: 窗口打开且选中目标文件" -ForegroundColor Green }
  else { Write-Host "  FAIL: 未选中目标文件" -ForegroundColor Red; $script:failed++ }
  foreach ($n in $new) { [DshFixWinChk]::CloseHandle($n) }
  Start-Sleep -Milliseconds 700
}

Write-Host "target: $Target"
Check 'real module (revealNativePath)' @("$PSScriptRoot\verify-reveal.cjs", $Target)
$env:NODE_OPTIONS = "--require=$PSScriptRoot\dsh-explorer-fix.cjs"
Check 'shim (unpatched-style URI call)' @("$PSScriptRoot\verify-shim.cjs", $Target)
Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue

if ($script:failed -eq 0) { Write-Host 'ALL PASS'; exit 0 }
Write-Host "$($script:failed) 项失败"; exit 1
