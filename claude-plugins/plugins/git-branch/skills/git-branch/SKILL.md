---
name: git-branch
description: Generate a conventional, kebab-case git branch name from a change description or staged diff. Use when the user asks to "create a branch", "name a branch", "what should I call this branch", or wants a branch name for upcoming work.
---

# Git Branch Namer

当你被激活时，根据用户描述的修改意图或当前的 staged/unstaged diff，生成**一个**符合规范的分支名。

## 核心规则

- **语言**：分支名必须使用 **English**。
- **格式**：只输出一个 Markdown 代码块，内部仅含一行分支名。
- **禁令**：**严禁**输出推理过程、解释说明或任何额外文字。

## 命名规范

类型前缀借鉴 [Conventional Commits](https://www.conventionalcommits.org/)：

`<type>/<short-kebab-case-description>`

| Type | 适用场景 |
|------|---------|
| `feature/` | 新功能 |
| `fix/` | bug 修复 |
| `refactor/` | 重构（行为不变） |
| `chore/` | 配置、依赖、脚手架 |
| `docs/` | 仅文档 |
| `test/` | 仅测试 |
| `perf/` | 性能优化 |

## 描述部分

- 全部小写，单词以 `-` 连接
- 控制在 3-5 个词
- 提取**意图**而非文件清单

## 示例输出

```text
feature/oauth-integration
```
