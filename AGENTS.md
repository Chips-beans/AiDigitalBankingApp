# Project instructions

When interacting with Cloudflare, use the cf CLI unless the project has a Wrangler configuration file.

Before continuing project work, read `docs/CURRENT_PROJECT_HANDOFF.md` and then the
task-specific documents linked there. This handoff records the current implemented
behavior, verification limits, intentionally stopped runtimes, and next steps.
Read `docs/NEXT_SESSION_BRIEF.md` for the consolidated current state and unresolved
issues before relying on the older chronological snapshots in the handoff.

The working tree contains substantial existing uncommitted and untracked work.
Preserve it; do not reset or clean it as part of setup. Keep credentials in the
ignored backend `.env` and out of documentation, logs, and Flutter builds.
