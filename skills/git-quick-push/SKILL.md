---
name: git-quick-push
description: Automates the process of adding, committing, and pushing changes to a Git remote repository. Use when the user requests to "push updates", "sync code", or "save changes to git".
---

# Git Quick Push

## Workflow

1.  **Check Status**: Execute `git status` to identify modified, added, or deleted files.
2.  **Stage Changes**: Execute `git add .` to stage all changes.
3.  **Generate Commit Message**: If the user didn't provide a message, analyze the changes and generate a concise, conventional-commit style message (e.g., `feat: ...`, `fix: ...`, `docs: ...`).
4.  **Commit**: Execute `git commit -m "<message>"` using the generated or provided message.
5.  **Identify Remote and Branch**: Check `git remote` and `git branch --show-current`.
6.  **Push**: Execute `git push <remote> <branch>`.

## Example Usage

### User: "推送更新"
1.  Analyze files changed (e.g., `main.go`, `README.md`).
2.  Run `git add .`.
3.  Commit: `git commit -m "feat: update backend and documentation"`.
4.  Push: `git push origin main`.

### User: "帮我提交代码，说明是修复了登录漏洞"
1.  Run `git add .`.
2.  Commit: `git commit -m "fix: resolve login security vulnerability"`.
3.  Push: `git push origin main`.
