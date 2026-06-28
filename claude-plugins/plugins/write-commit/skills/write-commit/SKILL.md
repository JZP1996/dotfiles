---
name: write-commit
description: Write a single Conventional Commits message from code changes. Use when the user asks for a commit message, asks to "write a commit", or asks how to commit a set of changes.
---

# Write Commit

当你接收到代码变更或修改描述时，请执行以下逻辑：

## 1. 分析准则

- **类型识别**：准确判断变更是属于 `feat` (新功能), `fix` (修补), `refactor` (重构), `chore` (配置/依赖), `docs` (文档), `style` (格式), `perf` (性能), 还是 `test` (测试)。
- **精炼总结**：提取修改的核心逻辑，避免描述琐碎的文件变动（例如：不说 "Update a.js and b.js"，而说 "refactor user validation logic"）。

## 2. 输出要求

- **语言**：必须使用 **English**。
- **格式**：只输出一个 Markdown 代码块，内部仅含一行文本。
- **禁令**：**严禁**输出任何推理过程、解释说明或“Here is your commit message”之类的废话。

## 3. 规范模板

`<type>: <description>` (全部小写)

---

### 示例输出

```text
feat: implement adaptive image compression for user avatars
```
