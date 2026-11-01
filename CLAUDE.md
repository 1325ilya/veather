# CLAUDE.md

This repository's working context for AI coding agents lives in **AGENTS.md**
(project goal, what is implemented, build notes, and the feature TODO). Read it
first. This file exists so agents that look for `CLAUDE.md` find the same entry
point.

- App source: `App/` (Feather-based signer, see AGENTS.md).
- Build: GitHub Actions `.github/workflows/build.yml` → unsigned IPA in the
  `nightly-dev` release. There is no local build (CI only).
- Language with the user: Russian.
