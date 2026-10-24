// verify-reveal.cjs — 用「当前部署」的真实 revealNativePath 打开并定位一个文件。
// 用法：node verify-reveal.cjs <file-path>
//
// 会自动在 npm 的 npx 缓存里找最新的 @deepseek-ai/dsh-native-command。
'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

function findModule() {
  const base = process.env.LOCALAPPDATA
    ? path.join(process.env.LOCALAPPDATA, 'npm-cache', '_npx')
    : null
  const found = []
  if (base && fs.existsSync(base)) {
    for (const dir of fs.readdirSync(base)) {
      const p = path.join(base, dir, 'node_modules', '@deepseek-ai', 'dsh-native-command', 'lib', 'index.js')
      if (fs.existsSync(p)) found.push(p)
    }
  }
  found.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)
  if (found.length === 0) throw new Error('dsh-native-command not found under %LOCALAPPDATA%\\npm-cache\\_npx')
  return found[0]
}

const target = process.argv[2]
if (!target) {
  console.error('usage: node verify-reveal.cjs <file-path>')
  process.exit(2)
}
const moduleFile = findModule()
console.log('module: ' + moduleFile)
import(pathToFileURL(moduleFile).href)
  .then(async (m) => {
    await m.revealNativePath(target, new AbortController().signal)
    console.log('revealNativePath OK: ' + target)
  })
  .catch((e) => {
    console.log('revealNativePath ERROR: ' + (e && e.message))
    process.exit(1)
  })
