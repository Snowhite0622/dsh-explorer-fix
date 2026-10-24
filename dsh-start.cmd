@echo off
rem dsh-start.cmd — 双击或终端运行即可启动 DSH（自带 explorer 修复双保险）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-start.ps1" %*
