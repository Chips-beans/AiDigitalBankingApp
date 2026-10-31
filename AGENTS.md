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

For Merchant App implementation, read `docs/MERCHANT_APP_PROGRESS.md` and
`docs/MERCHANT_M0_CONTRACTS.md` alongside the milestone plan. Keep progress and
handoff evidence current at milestone boundaries. Check the available Codex usage
tool before milestones and during long tasks; when either available usage window
has less than 10% remaining, save a detailed progress/handoff report, update the
session brief, and notify the user. Unavailable usage data is not zero. This is a
reporting threshold, not an instruction to pause or abandon authorized work.
