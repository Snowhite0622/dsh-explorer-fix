# dsh-explorer-fix

> 修复 DeepSeek Harness（DSH）Web 界面中「在文件资源管理器中显示」失效的问题。
>
> 适用：Windows 10/11 + dsh Web（实测 Windows 11 26200，dsh 0.1.5-rc.1 / 0.1.5-rc.2）

## 快速修复（3 步）

```powershell
# 1) 修复当前所有 dsh 部署（幂等，可反复运行）
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-patch.ps1

# 2) 重启 dsh web（模块在进程内缓存，必须重启才生效）

# 3) 验证：打开会话末尾的文件卡片 → ▾ 菜单 →「在文件资源管理器中显示」
#    预期：窗口打开且目标文件被选中
```

> 更稳妥：用 `.\dsh-start.cmd` 启动（自动修复 + 版本无关垫片），并按需运行
> `install-autorepair.ps1` 注册登录时自动巡检。

## 问题现象

DSH 会话末尾的**交付文件卡片**有一个「在文件资源管理器中显示」菜单项。在 Windows 上点击后：

1. **第一层问题**：窗口完全不出现（请求返回成功，界面显示"已请求在文件资源管理器中显示"，但没有任何窗口）。
2. **第二层问题**：窗口出现了，但**文件没有被选中/定位**（只打开了桌面或父文件夹）。

## 根因

两个相互独立、叠加出现的 bug，都在 DSH 的 `@deepseek-ai/dsh-native-command` 包里：

### 根因 1：`windowsHide` 抑制了 GUI 窗口

`runNativeCommand` 对**所有**子进程设置 `windowsHide: true`（等价 CREATE_NO_WINDOW）：

```js
execFile(command, [...args], {
  encoding: "utf8",
  signal,
  windowsHide: true
}, ...)
```

`explorer.exe` 是 GUI 程序：以 CREATE_NO_WINDOW 启动时窗口被抑制，但进程**仍以退出码 1 结束**；而 `revealNativePath` 把"退出码 1"当作"已转交"接受（explorer 分支的 catch），于是整条链路上报成功、实际无窗口。

### 根因 2：`file:///` URI 不被 `/select,` 接受

`revealNativePath` 把路径转成 file URI 作为 `/select,` 参数：

```js
const target = pathToFileURL(windowsPath, { windows: true }).href.replaceAll(",", "%2C");
await run("explorer.exe", ["/select,", target], signal);
```

在 Windows 11 26200 实测：`/select, file:///...` 只会打开桌面、不定位文件；而 `/select, <普通路径>`（**两参数形式**）才能正确打开并选中。单参数 `/select,<path>` 在路径含空格时也会失败。

## 修复

### 磁盘补丁（持久，推荐）

改 `node_modules/@deepseek-ai/dsh-native-command/lib/index.js` 两处：

```js
// 1) runNativeCommand 中：仅 explorer 不隐藏
windowsHide: !/^explorer(?:\.exe)?$/i.test(command)

// 2) revealNativePath 中：URI → 普通路径，保留 ["/select,", target] 两参数形式
const target = windowsPath;
```

### 运行时垫片（版本无关，推荐）

`dsh-explorer-fix.cjs` 通过 `NODE_OPTIONS=--require` 预加载，在 DSH 模块加载前猴子补丁 `child_process.execFile`：

- 对 `explorer(.exe)` 强制 `windowsHide: false`；
- 把 `/select,` 的 file URI 参数规整为普通路径（两参数形式）。

**不修改磁盘文件、不依赖 dsh 版本/缓存目录**，升级后依然生效（已验证对 ESM 的 `import { execFile }` 生效）。

## 组成文件

| 文件 | 说明 |
|------|------|
| `dsh-explorer-fix.cjs` | 运行时垫片（`NODE_OPTIONS=--require` 挂载） |
| `dsh-patch.ps1` | 就地修复器：扫描所有 npx 缓存目录 + 全局 npm，修复 `dsh-native-command`；幂等、带备份、支持 `-Check` |
| `dsh-start.ps1` / `dsh-start.cmd` | 启动器：materialize 版本 → 修复 → 挂垫片 → 启动 `dsh web` |
| `dsh-patch-launch.vbs` | 无窗口启动器：wscript 隐藏运行 `dsh-patch.ps1`（自定位路径，计划任务用它，不会闪控制台窗口） |
| `install-autorepair.ps1` | 注册计划任务：默认**登录时运行一次**（隐藏无窗口）；`-Every30Min` 改为每 30 分钟巡检（同样无窗口）；`-Remove` 卸载 |
| `verify-final.ps1` | 自检：真实模块 + 垫片各测一次「打开 + 选中」 |
| `verify-reveal.cjs` / `verify-shim.cjs` | 自检用辅助脚本（自动定位 npx 缓存里的模块） |

## 快速使用

```powershell
# 1) 修复已存在的所有 dsh 部署（幂等，可反复跑）
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-patch.ps1

# 2) 声明式自检（会真实弹出一次资源管理器窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-final.ps1

# 3) 以后用启动器启动（自动带修复；可 -Version 指定版本）
.\dsh-start.cmd

# 4) 安装自动巡检（默认：登录时运行一次，隐藏无窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-autorepair.ps1
#    可选：每 30 分钟巡检（同样隐藏无窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-autorepair.ps1 -Every30Min
# 卸载：schtasks /Delete /TN DshExplorerFixAutoRepair /F
```

## 注意事项（重要）

1. **补丁随 dsh 升级失效**：磁盘补丁作用于 npx 缓存中的 vendor 文件；dsh 升级/重装会换缓存目录，需要重打。因此本工具提供三层兜底：运行时垫片（版本无关）、启动器（启动即修复）、计划任务（登录时/每 30 分钟巡检，均可选）。
2. **垫片依赖启动方式**：`NODE_OPTIONS` 只对用 `dsh-start.cmd` 启动的进程生效。用其他方式启动时依赖磁盘补丁（计划任务会补，但已启动的进程不会热加载，需重启）。
3. **只影响 explorer.exe**：垫片与补丁只改 `explorer` 的调用，其他命令的 console 隐藏行为不变。
4. **备份**：`dsh-patch.ps1` 首次修改文件前会生成 `index.js.dshwhale-fix.bak`；需要回滚时复制回去即可。
5. **计划任务按用户注册，默认“登录时一次”**：任务名 `DshExplorerFixAutoRepair`；通过 `dsh-patch-launch.vbs`（wscript 隐藏）运行，**不会弹控制台窗口**。注意：`powershell.exe -WindowStyle Hidden` 仍会先让 conhost 闪一下，所以必须用 wscript 包装。部分受限终端（沙箱/非交互上下文）创建“登录时”触发会被拒，安装器会提示并回退为“每 30 分钟”计划（同样无窗口）。
6. **启动前先退出旧的 dsh web**：`dsh-start.cmd` 会和已有实例争用 3080 端口。
7. **脚本编码**：`.ps1` 必须保存为 **UTF-8 with BOM**——Windows PowerShell 5.1 会把无 BOM 的 UTF-8 脚本按 GBK 误读，导致中文乱码甚至解析异常。
8. **平台范围**：仅 Windows（`explorer.exe` 分支）。macOS 用 `open -R`、Linux 用 `xdg-open`，不受此 bug 影响。
9. **上游修复是最好的长期方案**：本工具是本地 workaround。建议同时向 `deepseek-ai/deepseek-harness` 提 issue（附下方草稿）。
10. **部署位置**：脚本可放在任意目录——计划任务与启动器都按脚本自身位置（`$PSScriptRoot` / `WScript.ScriptFullName`）定位，无需改路径。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

## 附录：给上游的 issue 草稿

> **标题**：Windows: 「在文件资源管理器中显示」无效 — `runNativeCommand` 对 explorer.exe 设置 windowsHide，且 `/select,` 使用 file URI
>
> **现象**：Windows 11 26200，点击交付文件卡片的「在文件资源管理器中显示」：请求返回成功（204），但 ①窗口不出现；②（绕过 ① 后）窗口出现但文件未被选中。
>
> **根因**：
> 1. `packages/*/native-command/lib/index.js`（`runNativeCommand`）对所有子进程设 `windowsHide: true`（CREATE_NO_WINDOW）。`explorer.exe` 为 GUI 程序，被 CREATE_NO_WINDOW 启动时窗口被抑制，但进程仍以退出码 1 返回；`revealNativePath` 把退出码 1 视为成功转交 → 静默失败。
> 2. 同文件 `revealNativePath` 用 `pathToFileURL(windowsPath, { windows: true }).href` 作为 `/select,` 参数；在 Windows 11 26200 上该形式不选中文件（仅打开桌面），而普通路径的两参数形式 `["/select,", windowsPath]` 可正确选中。单参数 `/select,<path>` 在含空格路径下也失败。
>
> **建议修复**：
> - `runNativeCommand`：对 `explorer(.exe)` 不设 `windowsHide`（GUI 程序不应带 CREATE_NO_WINDOW）；
> - `revealNativePath`：直接传普通路径，保留两参数形式 `["/select,", windowsPath]`。
