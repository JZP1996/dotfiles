# Creating Skills

Skills are domain knowledge modules that Claude automatically applies based on context matching. They extend Claude's capabilities without requiring explicit invocation.

## When to Create a Skill

Create a skill when:
- Claude should automatically apply domain knowledge for certain topics
- The same guidance is needed repeatedly across sessions
- Context-specific expertise should be available to all users (or just you)

## Skill Anatomy

```
my-skill/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata
├── skills/
│   └── SKILL.md              # Skill content with YAML frontmatter (required)
├── references/               # Detailed docs loaded as needed (optional)
├── scripts/                  # Executable utilities (optional)
└── assets/                   # Output resources — templates, images (optional)
```

## Progressive Disclosure

Skills use a three-level loading system:

1. **Metadata** (name + description) — always in context (~100 words)
2. **SKILL.md body** — loaded when skill triggers (<5K words)
3. **Bundled resources** — loaded as needed by Claude (unlimited)

Keep SKILL.md lean (target 1,500–2,000 words). Move detailed content to `references/` files.

## Creating a Skill: Step-by-Step

### Step 1: Understand the Skill

Before creating files, identify concrete usage examples:
- What tasks should the skill support?
- What would a user say that should trigger it?
- What reusable resources (scripts, references, assets) would help?

### Step 2: Plan Resources

Analyze usage examples to identify reusable resources:
- **`scripts/`** — Include when code is rewritten repeatedly or deterministic reliability is needed
- **`references/`** — Include for detailed documentation Claude consults while working. Keeps SKILL.md lean
- **`assets/`** — Include for files used in output (templates, boilerplate code)

Create only directories needed for the skill.

### Step 3: Create Files (Tier-Specific)

#### Personal Tier

Personal skills live in `skills/local/` within the claude-plugins directory.

**Create from template:**

```bash
cd skills/local
cp -r example-skill.template/ my-new-skill/
```

**Edit `my-new-skill/.claude-plugin/plugin.json`:**

```json
{
  "name": "my-new-skill",
  "version": "1.0.0",
  "description": "Brief description shown in plugin list"
}
```

**Edit `my-new-skill/skills/SKILL.md`:**

```markdown
---
name: my-new-skill
description: "This skill should be used when the user asks to 'trigger phrase 1',
  'trigger phrase 2', or 'trigger phrase 3'. Provides guidance on [domain]."
---

# My New Skill

[Purpose of the skill in 1-2 sentences.]

## Instructions

[Core procedures and workflows in imperative form.]
```

**Register in `skills/local/.claude-plugin/marketplace.json`:**

```json
{
  "plugins": [
    {"name": "my-new-skill", "source": "./my-new-skill", "description": "Brief description"}
  ]
}
```

**Enable in `.claude/settings.local.json`** (create if it does not exist):

```json
{
  "enabledPlugins": {
    "my-new-skill@local-skills": true
  }
}
```

Use `settings.local.json` for personal skills — not `settings.json` (which is committed to git).

#### Niche Tier (Repo-Specific)

Niche skills live in `.claude/skills/` within the target repository. Claude Code auto-discovers skills in this location — no marketplace registration needed.

**Create directory structure:**

```bash
mkdir -p .claude/skills/my-repo-skill/.claude-plugin
mkdir -p .claude/skills/my-repo-skill/skills
```

**Create `.claude/skills/my-repo-skill/.claude-plugin/plugin.json`:**

```json
{
  "name": "my-repo-skill",
  "version": "1.0.0",
  "description": "Repo-specific skill. Use when [trigger context]."
}
```

**Create `.claude/skills/my-repo-skill/skills/SKILL.md`:**

```markdown
---
name: my-repo-skill
description: "This skill should be used when the user asks to 'trigger phrase 1',
  'trigger phrase 2', or troubleshoot [repo-specific domain]."
---

# My Repo Skill

[Instructions for repo-specific workflows.]
```

**Enable in `.claude/settings.json`** (project-level, committed to git):

```json
{
  "enabledPlugins": {
    "my-repo-skill": true
  }
}
```

Open a PR with the new skill for standard code review.

#### Org-Specific Tier

Org-specific skills live in your organization's agents repository (e.g., `edge-agents/plugins/`).

**Create directory structure:**

```bash
mkdir -p plugins/my-org-skill/.claude-plugin
mkdir -p plugins/my-org-skill/skills
```

**Create `plugins/my-org-skill/.claude-plugin/plugin.json`:**

```json
{
  "name": "my-org-skill",
  "version": "1.0.0",
  "description": "Org-wide skill. Use when [trigger context]."
}
```

**Create `plugins/my-org-skill/skills/SKILL.md`:**

```markdown
---
name: my-org-skill
description: "This skill should be used when the user asks to 'org-specific action',
  'deploy to org infrastructure', or troubleshoot [org domain]."
---

# My Org Skill

## Security Boundaries

This skill follows the [Security Principles](../../shared/security-principles.md).

**This skill:**
- **CAN**: [allowed operations]
- **CANNOT**: [prohibited operations]
- **MUST CONFIRM**: [operations requiring confirmation]

## Instructions

[Org-specific workflows and procedures.]
```

**Register in the org marketplace (`.claude-plugin/marketplace.json` at repo root):**

```json
{
  "plugins": [
    {"name": "my-org-skill", "source": "./plugins/my-org-skill", "description": "Org skill description"}
  ]
}
```

Open a PR for org CODEOWNERS review. See `docs/org-agents-guide.md` for full setup details.

#### General Tier (claude-plugins)

General skills serve all teams and require security review.

**Create directory structure:**

From the claude-plugins repository root:

```bash
mkdir -p plugins/my-general-skill/.claude-plugin
mkdir -p plugins/my-general-skill/skills
```

**Create `plugins/my-general-skill/.claude-plugin/plugin.json`:**

```json
{
  "name": "my-general-skill",
  "version": "1.0.0",
  "description": "Universal skill. Use when [trigger context]."
}
```

**Create `plugins/my-general-skill/skills/SKILL.md`:**

```markdown
---
name: my-general-skill
description: "This skill should be used when the user asks to 'common action',
  'general workflow', or 'cross-team operation'."
---

# My General Skill

## Security Boundaries

This skill follows the [Security Principles](../../shared/security-principles.md).

**This skill:**
- **CAN**: [allowed operations]
- **CANNOT**: [prohibited operations]
- **MUST CONFIRM**: [operations requiring confirmation]

## Instructions

[Universal procedures applicable to all teams.]
```

**Register in the claude-plugins marketplace (`.claude-plugin/marketplace.json` at repo root).**

Open a PR for CODEOWNERS + security review. See `plugins/SKILLS.md` for contribution guidelines.

### Step 4: Configure Writing Style

**Writing style requirements (all tiers):**

- Write the body in **imperative/infinitive form** (verb-first): "To accomplish X, do Y" — not "You should do X"
- Write the frontmatter description in **third person**: "This skill should be used when..." — not "Use this skill when..."
- Include **specific trigger phrases** in the description that match what users would say
- Reference all bundled resources (scripts, references, assets) so Claude knows they exist

### Step 5: Validate and Iterate

**Restart Claude Code** to pick up the new plugin, then verify:

1. Skill appears in `/plugin` list
2. Asking trigger phrases activates the skill
3. Content is helpful for the intended tasks

**Iterate based on usage:**
- Strengthen trigger phrases if the skill does not activate reliably
- Move long sections from SKILL.md to `references/` if context is bloated
- Add scripts for operations that require deterministic reliability
- Add examples for working code users can copy and adapt

## Common Mistakes

### Weak trigger description

**Bad:**
```yaml
description: "Provides guidance for deployment."
```
Vague, no specific trigger phrases, not third person.

**Good:**
```yaml
description: "This skill should be used when the user asks to 'deploy to production',
  'run deployment', or 'rollback a release'. Provides deployment procedures for MyService."
```
Third person, specific phrases, concrete scenarios.

### Too much content in SKILL.md

**Bad:** A single 4,000-word SKILL.md with all documentation inline.

**Good:** A 1,500-word SKILL.md with `references/detailed-guide.md` for extended content.

### Second-person writing style

**Bad:** "You should start by reading the configuration file."

**Good:** "Start by reading the configuration file."

### Unregistered or mismatched names

All names must match: directory name, `plugin.json` name, SKILL.md frontmatter name, and marketplace entry name. A mismatch prevents skill discovery.
