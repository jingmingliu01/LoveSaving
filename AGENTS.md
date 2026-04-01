# Repository Notes

## Documentation Paths

- Never write developer-specific absolute filesystem paths like `/Users/jimmy/...` in repository documentation.
- In docs meant to live in the repo or render on GitHub, always use repo-relative paths, for example:
  - `Backend/insights-service/README.md`
  - `Docs/working/plans/ai-insights-local-backend-runbook_2026-03-31.md`
- Absolute local paths are only acceptable in transient chat responses where clickable local file references are required by the Codex desktop app.
