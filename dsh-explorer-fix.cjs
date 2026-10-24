'use strict'
/**
 * dsh-explorer-fix.cjs — 预加载修复垫片（NODE_OPTIONS=--require 挂载）。
 *
 * 修复两个 explorer 行为问题（与 dsh 版本/目录无关，升级不失效）：
 *  1) @deepseek-ai/dsh-native-command 的 runNativeCommand 对所有子进程设
 *     windowsHide: true（CREATE_NO_WINDOW）→ explorer 窗口被抑制、却仍返回
 *     退出码 1 → 「在文件资源管理器中显示」静默失败。
 *  2) revealNativePath 用 file:/// URI 作为 /select, 参数 → Win11 上打开但
 *     不选中文件。改为普通 Windows 路径；保留两参数形式 ["/select,", 路径]
 *     （实测对带空格/逗号的路径也可靠；单参数形式对空格路径无效）。
 *
 * 实现：在 Node 启动时（早于 DSH 模块加载）猴子补丁 child_process.execFile。
 */
const cp = require('node:child_process')
const { fileURLToPath } = require('node:url')
const isExplorer = (file) => typeof file === 'string' && /^explorer(?:\.exe)?$/i.test(file)

function toPlainPath(value) {
  if (typeof value !== 'string') return value
  if (!value.startsWith('file:')) return value
  try { return fileURLToPath(value) } catch { return value }
}

/** /select, 调用规整为 ['/select,', <普通路径>]；无法解析时原样返回。 */
function normalizeSelectArgs(args) {
  if (!Array.isArray(args) || args.length === 0) return args
  const first = args[0]
  if (typeof first !== 'string') return args
  if (first === '/select,') {
    if (typeof args[1] !== 'string') return args
    return ['/select,', toPlainPath(args[1])]
  }
  if (first.startsWith('/select,')) {
    const rest = first.slice('/select,'.length)
    if (rest === '') return args
    return ['/select,', toPlainPath(rest)]
  }
  return args
}

function patchExecFile(name) {
  const orig = cp[name]
  if (typeof orig !== 'function' || orig.__dshExplorerFix) return
  const patched = function (file, ...rest) {
    if (isExplorer(file)) {
      // 1) 规整 /select, 参数（URI → 普通路径，保持两参数形式）
      if (rest.length > 0) rest[0] = normalizeSelectArgs(rest[0])
      // 2) explorer 是 GUI：不能带 windowsHide，否则窗口被抑制
      const optIndex = rest.findIndex(
        (value) => value !== null && typeof value === 'object' && !Array.isArray(value),
      )
      if (optIndex >= 0) {
        rest[optIndex] = Object.assign({}, rest[optIndex], { windowsHide: false })
      } else if (typeof rest[rest.length - 1] === 'function') {
        rest.splice(rest.length - 1, 0, { windowsHide: false })
      } else {
        rest.push({ windowsHide: false })
      }
    }
    return orig.call(this, file, ...rest)
  }
  patched.__dshExplorerFix = true
  cp[name] = patched
}

patchExecFile('execFile')
