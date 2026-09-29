import { cp, mkdir, rm } from 'node:fs/promises'
import { basename, relative, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const source = resolve(root, 'assets/web_reader/foliate-js')
const target = resolve(root, 'out/assets/web_reader/foliate-js')

await mkdir(resolve(root, 'out/assets/web_reader'), { recursive: true })
await rm(target, { recursive: true, force: true })
await cp(source, target, {
  recursive: true,
  filter: path => {
    const rel = relative(source, path)
    const parts = rel.split(/[\\/]/)
    const name = basename(path)
    return !parts.some(part => ['.github', 'rollup', 'tests', 'node_modules'].includes(part))
      && !/\.(map|md|log)$/i.test(name)
      && !['eslint.config.js', '.gitignore', '.gitattributes'].includes(name)
  },
})
console.log('Copied the offline book reader into out/assets/web_reader/foliate-js')
