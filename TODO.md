Awesome — here’s a patched, ready-to-implement checklist with all the fixes baked in. It’s ultra-granular and uses [ ] boxes so you (or an engineer) can literally tick things off while building. I’ve folded in the must-fixes (tmux name, quoting, portability, races, etc.) and kept the original flow, but corrected and hardened each step.

⸻

wtx worktree/mux launcher — Patched Implementation Checklist

Conventions used below:
	•	✔ means a quick rationale; code blocks show the exact incantations to copy.
	•	Steps are idempotent unless marked otherwise.
	•	Everything is Bash (#!/usr/bin/env bash), no zsh-isms.

⸻
Caveats

0.0 [x] be compatible with the old Mac OS bash version etc.

0) Shell hygiene & mode

[ ] 0.2 Verify minimum tools (log and skip gracefully)

need() { command -v "$1" >/dev/null 2>&1; }

	•	Required: git
	•	Optional/auto: tmux or screen
	•	Optional features: uv, pnpm

⸻

1) Bootstrap & globals

[ ] 1.1 Parse args: NAME?, -c CMD?, --no-open?, --mux?, --from REF?, --dry-run?, --verbose?, --delete-branches?
⸻

2) Detect mux backend

⸻

3) Determine parent & branch name (safe, race-free)

⸻

4) Ensure branch exists + metadata (robust quoting)

⸻

5) Worktree creation & path (repair zombies)

⸻

6) Shared uv env (optional, logged)

⸻

7) pnpm install (guarded, stamped)

⸻

8) Session naming (tmux/screen safe)

⸻

9) Create or attach session

tmux path

⸻

10) Readiness & raw keystrokes (-c)

[ ] 10.1 tmux ready probe (safe alias)

⸻

11) Messaging (parent/children) — optional

[ ] 11.1 tmux sessions discovery by @wtx_repo_id
[ ] 11.2 Compose comment line (no side effects)
[ ] 11.3 Send via send-keys to targets (guard with policy flag)

⸻

12) Prune (wtx prune)

[ ] 12.1 Enumerate mux sessions; kill those whose worktree dirs vanished (dry-run first)
[ ] 12.2 Compare $WORKTREE_ROOT/* vs git worktree list → remove orphan dirs (dry-run)
[ ] 12.3 Optionally delete merged refs/heads/wtx/* only with --delete-branches
[ ] 12.4 Print a columnar dry-run report before doing anything destructive

⸻

13) Logging

⸻

14) Concurrency cleanup

⸻

15) Tests (bats/bash)

[ ] 15.5 Ready flag set/read
[ ] 15.6 Prune dry-run vs real
[ ] 15.7 Both tmux and screen modes (if available)
[ ] 15.8 Attach while already inside tmux → switch-client works

⸻

16) Docs

[ ] 16.1 Flags & env vars (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY, MUX, WTX_PROMPT)
[ ] 16.2 Examples (wtx -c 'pytest -q') + attach instructions
[ ] 16.3 Security note: raw keystrokes; no auth/protocol by design
[ ] 16.4 Troubleshooting: zombie worktrees; PNPM missing; macOS flock fallback

⸻

17) Nits & polish

[ ] 17.2 Log that chmod 700 ran (surprising on shared boxes)
⸻

Example final banner (single line)

wtx: repo=my-repo branch=wtx/main-003 parent=main from=HEAD actions=[env:linked, pnpm:skipped, session:created]


⸻

