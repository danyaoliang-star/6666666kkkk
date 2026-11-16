// Syntax-only check for hosts without Xcode. This does not type-check Apple SDK APIs.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
const root = path.dirname(fileURLToPath(import.meta.url))
const modules = path.resolve(root, '../.runtime/native-validation/node_modules')
const module = await import(pathToFileURL(path.join(modules, 'web-tree-sitter/tree-sitter.js')))
const Parser = module.default
await Parser.init()
const language = await Parser.Language.load(path.join(modules, 'tree-sitter-wasms/out/tree-sitter-swift.wasm'))
const parser = new Parser()
parser.setLanguage(language)
let errors = 0
let count = 0
for (const folder of ['FamilyHealth', 'FamilyHealthTests']) {
  if (!fs.existsSync(path.join(root, folder))) continue
  for (const name of fs.readdirSync(path.join(root, folder)).filter(name => name.endsWith('.swift')).sort()) {
    const source = fs.readFileSync(path.join(root, folder, name), 'utf8')
    const tree = parser.parse(source)
    const visit = node => {
      if (node.type === 'ERROR' || node.isMissing()) {
        errors++
        console.error(`${folder}/${name}:${node.startPosition.row + 1}:${node.startPosition.column + 1}: ${node.type} ${JSON.stringify(source.slice(node.startIndex, Math.min(node.endIndex, node.startIndex + 160)))}`)
      }
      for (const child of node.children) visit(child)
    }
    visit(tree.rootNode)
    tree.delete()
    count++
  }
}
parser.delete()
console.log(`Parsed ${count} Swift files; ${errors} syntax errors. Apple SDK type-check and simulator tests still require Xcode.`)
process.exitCode = errors ? 1 : 0
