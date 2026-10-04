# 构建依赖安全记录

## braces 3.0.3 深层模式防护（2026-10-04）

- 公告：[GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm)。注册表当前仍只提供 3.0.3，不能声称上游版本已修复。
- 使用路径：Tailwind 3 的 chokidar、micromatch、fast-glob；不属于阅读器运行时依赖。
- 本地补丁：`patches/braces@3.0.3.patch`。解析堆栈最多 64 层；compile、expand、stringify 在递归前用迭代校验拒绝深层 AST 与重复节点。调用者不能通过选项解除限制。
- `node scripts/audit-dependencies.cjs` 在审计前检查实际 Tailwind 依赖实例，验证 100/1000/10000 层大括号、括号、不平衡输入、深层/循环 AST 被安全拒绝，并验证正常 glob 输出。
- 仅在这些防护检查通过后，将该公告、该包、该版本且仅开发依赖的结果记为“本地缓解”。其他公告、注册表错误和补丁失效都会阻断 CI。原始 `pnpm audit` 仍会报告此公告，不能将其描述为零漏洞。
- 限制：超过防护深度的合法复杂构建 glob 也会被拒绝；项目当前使用的 glob 与生产构建必须通过验证。补丁不声称解决公告以外的所有资源耗尽方式。
- 上游修复版本可用后，优先升级并删除本地补丁与这一条限定豁免；升级时重新运行构建和跨端阅读验收。
