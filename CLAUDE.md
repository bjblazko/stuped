# Claude Code Instructions

## Documentation

When making code changes, always update all relevant documentation:

- `CHANGELOG.md` — add entry under `[Unreleased]` for any user-facing change
- `README.md` — update if features, requirements, or usage changed
- `doc/spec/*.md` — update the relevant spec if behavior changed
- `doc/adr/` — add a new ADR if an architectural decision was made or changed; update `doc/adr/index.md`
- `doc/arc42.md` — update if architecture, deployment, or quality characteristics changed

Use Mermaid (not ASCII art) for all diagrams.

## Releasing a new version

To cut a GitHub release (triggered by a `v*` tag via `.github/workflows/release.yml`):

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Move `[Unreleased]` entries in `CHANGELOG.md` to a new `[X.Y.Z] - YYYY-MM-DD` section; leave an empty `[Unreleased]` block above it
3. Update `CLAUDE.md` if the release process changed
4. Commit all changes, then create and push the tag:
   ```
   git tag vX.Y.Z && git push origin main && git push origin vX.Y.Z
   ```
   The version shown in the About dialog comes from `MARKETING_VERSION` via `CFBundleShortVersionString` — no Swift code change needed.
