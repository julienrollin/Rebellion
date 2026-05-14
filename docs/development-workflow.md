# Development Workflow

Use two repositories.

## Private Workspace

`Rebellion_Experimental` is the private working copy. Codex can use internal notes, memory search, reverse-engineering notes, probes, logs, and local deployment targets there.

Use any private local path. Keep this repository separate from the public `Rebellion` clone.

## Public Workspace

`Rebellion` is the public release repo. It contains only allowlisted release files, docs, and public install tooling.

Use a separate local clone of the public GitHub repository.

## Promotion

From the public repo:

```powershell
.\tools\promote-from-experimental.ps1 -ExperimentalRoot "<path-to-private-experimental-repo>"
.\tools\check-public-hygiene.ps1
```

The promotion script copies only paths listed in `tools/promote-allowlist.txt`.

## Rules

- Do not copy private research, binary-analysis output, debugger logs, memory databases, or local deployment backups into `Rebellion`.
- Do not commit `.agent-backups`, `share`, `research`, `plans`, `artifacts`, `tests`, or local package drops.
- Keep public changes as clean release commits.
- Push only from `Rebellion`.
