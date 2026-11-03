# Project instructions

When interacting with Cloudflare, use the cf CLI unless the project has a Wrangler configuration file.

Before continuing project work, read `docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md`. It records
the current status, agent rules, environment setup, commands, conventions, known limits and
next steps. Then read the product document for the area you touch:

- `docs/CUSTOMER_APP.md` — Customer App and the shared banking backend.
- `docs/MERCHANT_APP.md` — Merchant App decisions, contracts and the build record (M0–M8, M9 plan).

Older per-milestone reports were consolidated into these three files; the last commit that
still has them is `ccc10bd` (`git show ccc10bd:docs/<NAME>.md`). Do not recreate per-milestone
report files; update the three documents instead.

Preserve existing work in the tree; never reset or clean it as part of setup. Keep credentials
in the ignored backend `.env` and out of documentation, logs, and Flutter builds.

Keep progress and handoff evidence current at milestone boundaries (guide §2 and §8). Check the
available usage tool before milestones and during long tasks; when either available usage window
has less than 10% remaining, save a detailed checkpoint in the progress guide and notify the
user. Unavailable usage data is not zero. This is a reporting threshold, not an instruction to
pause or abandon authorized work.
