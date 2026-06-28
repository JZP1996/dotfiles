---
name: write-pr
description: Write a PR title and description from the current branch diff. Use when the user asks to "write a PR", "draft a pull request", "generate PR description", or is about to open a PR.
---

# Write PR

当你被激活时，请基于**当前分支与主分支的差异**生成 PR 标题与描述。

## 1. 收集变更

按以下顺序探测主分支（取第一个存在的）：

1. `origin/main`
2. `origin/master`
3. `main`
4. `master`

使用以下命令收集信息：

```bash
git log --oneline <main>..HEAD            # 提交列表
git diff --stat <main>...HEAD             # 文件统计
git diff <main>...HEAD                    # 完整 diff（用于理解意图）
```

如果当前就在主分支上，或没有差异，**直接告知用户**，不要编造内容。

## 2. 输出规范

按顺序输出 **2 个** 独立的 Markdown 代码块：

### Block 1: PR Title

- **格式**：`<type>: <description>`（遵循 Conventional Commits）
- **要求**：单行、英文、首字母小写、不加句号
- **type**：feat, fix, docs, style, refactor, perf, test, chore

示例：

```text
feat: integrate google oauth2 provider
```

### Block 2: PR Description

```markdown
## Summary

A one or two sentence overview of what this PR does and why.

## Changes

- Key technical change A
- Key technical change B
- Key technical change C

## Notes

(Optional) Anything reviewers should know: migrations, follow-ups, risks.
```

填充规则：

- **Summary**：高层意图，不是文件清单
- **Changes**：3-7 条，每条对应一个内聚的变更点
- **Notes**：仅在确有需要时保留；否则**整段删掉**
- 全部使用 **English**

## 禁令

- 不要输出推理过程、寒暄、`Here is...` 之类
- 不要凭空编造未在 diff 中出现的内容
- 不要 mention AI / Claude / Copilot 等工具
