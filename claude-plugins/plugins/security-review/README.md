# Security Review Plugin

Security-focused code review for pull requests. Detects vulnerabilities, secret exposure, and security misconfigurations.

## Overview

This plugin provides comprehensive security analysis for PR reviews, covering:

- **Authentication & Authorization** - Token handling, credentials, permissions, access control
- **Cryptography** - Key management, encryption, hashing, randomness
- **Attack Surface** - New entry points, API endpoints, user inputs
- **Infrastructure** - System topology, services, databases, deployment
- **Information Disclosure** - PII, sensitive data, error messages
- **Deserialization** - Unsafe deserialization patterns
- **CSRF** - Missing anti-CSRF protections
- **Secret Management** - Hardcoded secrets, certificate validation
- **SSRF** - Server-side request forgery risks

## When It Activates

The skill is designed to be invoked by the `code-reviewer` agent during PR reviews. It can also be manually invoked when you:

- Ask for a "security review" of code changes
- Request "security analysis" of a PR
- Want to check for vulnerabilities in code

## Key Behaviors

- Analyzes **added lines only** (not deleted code)
- Skips test code (files with `test`/`spec`/`mock` in path)
- Only reports issues with **>=80% confidence**
- Provides severity ratings: Critical, High, Medium, Low
- Suggests remediation with links to secure coding best practices

## Usage

```
# During PR review (automatic via code-reviewer)
# Or manually invoke:
"Perform a security review of this PR"
"Check these changes for security issues"
```

## Installation

This plugin is included in the claude-plugins marketplace. Enable it with:

```bash
/plugin enable security-review
```

## Attribution

Security review prompt provided by the AppSec team.
