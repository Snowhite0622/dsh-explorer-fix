// verify-shim.cjs — 模拟「未修复的 DSH 调用形式」（两参数 + file URI）在预加载垫片下的行为。
// 用法（垫片通过 NODE_OPTIONS 挂载）：
//   set NODE_OPTIONS=--require=.\dsh-explorer-fix.cjs
//   node verify-shim.cjs <file-path>
'use strict'
const { execFile } = require('node:child_process')
const { pathToFileURL } = require('node:url')

const target = process.argv[2]
if (!target) {
  console.error('usage: node verify-shim.cjs <file-path>')
  process.exit(2)
}
const uri = pathToFileURL(target, { windows: true }).href.replaceAll(',', '%2C')
console.log('shim test: execFile("explorer.exe", ["/select,", <file-uri>], { windowsHide: true })')
execFile('explorer.exe', ['/select,', uri], { windowsHide: true }, (err) => {
  console.log('execFile cb: ' + (err ? String(err.code) : 'ok'))
})
