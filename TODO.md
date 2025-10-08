Awesome — here’s the focused IMPLEMENTATION PLAN for all remaining (not yet built) items from the PRD. Everything already shipped lives in TODO_DONE.md. Keep this <200 lines; collapse once complete.

Legend
  [ ] = not started  [~] = in progress  [x] = done (move to TODO_DONE.md soon)  (Pxx) = PRD point reference
  ☐ subtask boxes may be checked independently.

⸻
0) Shell hygiene & mode (residual)
[ ] 0.2 (P6 prereq) need() hardening & tool verification
    ☐ implement need() once at top (already drafted) — keep pure POSIX test
    ☐ on startup: require git; capture missing into MISSING=()
    ☐ detect at least one of tmux|screen; else exit 2 with hint
    ☐ optional: uv, pnpm; log if absent (no fatal)
    ☐ log summary: "tools: git:ok tmux:ok screen:skip uv:miss pnpm:ok" -> stderr

⸻
1) Arg parsing (P6, P12–P16, P65a/99)
[ ] 1.1 Robust parser
    ☐ Support: NAME?  -c CMD  --no-open  --mux {auto,tmux,screen}  --from REF
    ☐ Reserved (unimplemented → hard error exit 78): --close --close-merge --close-force
    ☐ Flags: --dry-run (only meaningful for separate wtx-prune tool), --verbose, --delete-branches (ignored here; used by wtx-prune), --no-git-logging
    ☐ Hidden internal flag for post-commit hook: --_post-commit (broadcast commit message)
    ☐ Implementation: while [[ $# -gt 0 ]]; do case $1 in ... esac
    ☐ Single positional (first non-flag) = NAME; extra → usage & exit 64
    ☐ usage(): concise help + env vars
    ☐ Export canonical vars: NAME CMD NO_OPEN MUX FROM_REF CLOSE_MODE GIT_LOGGING=0/1 INTERNAL_POST_COMMIT=0/1
    ☐ Validate mutually exclusive (close flags) even though unimplemented

⸻
2) Detect mux backend (completed previously) — no action

⸻
3) Determine parent & numbering (completed) — monitor for race regressions

⸻
4) Branch metadata (completed) — add from_ref already done

⸻
5) Worktree creation & repair (completed) — add metrics output later (see 17)

⸻
6) Per-repo uv env (P26–P29, P95)
[ ] 6.1 Default path now: $(git rev-parse --git-common-dir)/../.venv (no migration logic needed)
[ ] 6.2 Honour $WTX_UV_ENV override
[ ] 6.3 Create with: uv venv "$WTX_UV_ENV" (idempotent)
[ ] 6.4 Activate: prepend bin to PATH in init script (ensure no duplicate prepend)
[ ] 6.5 Test: create two branches → env created once (see Tests section)

⸻
7) pnpm install (implemented) — add test for lockfile change (P79)

⸻
8) Session naming (implemented) — ensure matches prune/messaging filters

⸻
9) Create / attach session (implemented) — extend attach for --no-open semantics when GUI added

⸻
10) Readiness probe (P39)
[ ] 10.1 tmux ready helper
    ☐ Provide function: wtx_tmux_ready() { tmux show-option -t "$SES_NAME" -v @wtx_ready 2>/dev/null | grep -q '^1$'; }
    ☐ Add small retry loop (5×40ms) to mitigate race with init script
    ☐ Screen: write readiness file "$WTX_GIT_DIR/state/$WORKTREE_NAME.ready" (NOT inside worktree) from init banner, then probe with [ -f ]. Avoids dirtying working tree.
    ☐ Expose CLI later if needed (defer)

⸻
11) Messaging (P49–P53)
[ ] 11.1 Session discovery (tmux first; screen deferred for messaging)
    ☐ tmux list-sessions -F '#{session_name}' | grep '^wtx\.'
    ☐ For each candidate read @wtx_repo_id; keep only matching current repo id
    ☐ Also store @wtx_branch (set during spinup) to avoid reverse-parsing names
[ ] 11.2 Relation map
    ☐ Load state JSON for each session (branch,parent_branch)
    ☐ Build: parent_of[child]=parent; children_of[parent]+=child
[ ] 11.3 Policy resolution (enum: parent|children|parent+children|all)
    ☐ parent → at most one direct parent (if any)
    ☐ children → direct children_of[current]
    ☐ parent+children → union
    ☐ all → BFS: queue starts with parent + children; while queue: pop b; add its parent (if any) and its children; maintain visited set (branch names) to prevent cycles
    ☐ Invalid value → error exit 64
[ ] 11.4 Commit hook installation (always)
    ☐ On every wtx run ensure .git/hooks/post-commit exists & contains wtx marker
    ☐ If absent: create executable hook with:
       #!/usr/bin/env bash\n[ -x "$(command -v wtx)" ] || exit 0\nwtx --_post-commit || true
    ☐ Idempotent: detect marker line '# wtx post-commit hook'
[ ] 11.5 Broadcast trigger
    ☐ Only on post-commit (hook path) → wtx invoked with --_post-commit
    ☐ Skip on spinup and -c (no duplication / spam)
[ ] 11.6 Compose message
    ☐ Fetch latest commit: git log -1 --pretty=format:'%h %s'
    ☐ Sanitize: replace newlines with spaces; strip control chars
    ☐ Format: "# [wtx] $BRANCH_NAME commit $SHORT_SHA \"$SUBJECT\""
[ ] 11.7 Send
    ☐ For each resolved target session: tmux send-keys -t session "$line" C-m (ignore failures unless --verbose)
[ ] 11.8 Cycle safety
    ☐ BFS visited set prevents infinite traversal even if parent pointers corrupted
[ ] 11.9 Tests: deep chain, cycle injection (manually edit parent), invalid policy, branch with slash & colon

⸻
12) Prune tool (separate executable wtx-prune) (P54–P61)
[ ] 12.1 Provide standalone script wtx-prune (no subcommand in main wtx)
[ ] 12.2 Enumerate:
    ☐ Sessions: tmux list-sessions; map via @wtx_branch & @wtx_repo_id
    ☐ Worktrees: git worktree list --porcelain
    ☐ FS dirs: $WORKTREE_ROOT/*
[ ] 12.3 Classify:
    ☐ Session only (missing dir) → kill-session
    ☐ Dir not registered in git worktree list & has state JSON → remove-dir (orphan)
    ☐ Branch wtx/* fully merged into its parent → candidate delete (only with --delete-branches)
       Algorithm: parent=$(jq .parent_branch state); if parent exists:
         git show-ref --verify refs/heads/$parent || skip
         git merge-base --is-ancestor $BRANCH $parent && branch fully merged
[ ] 12.4 Dry-run default unless --yes provided (explicit flag for this tool)
[ ] 12.5 Column report: TYPE TARGET ACTION(REASON) (prefix DRY- for dry-run)
[ ] 12.6 Execution order: kill sessions → git worktree remove --force → branch delete → git worktree prune
[ ] 12.7 Safety: enforce ^wtx/ regex for any branch deletion
[ ] 12.8 Exit codes: 0 success; 3 partial failures (collect errors)
[ ] 12.9 Lock: $WTX_GIT_DIR/locks/prune.lockdir (timeout 10s then stale warn & reuse)
[ ] 12.10 Tests: orphan dir, missing dir w/ session, merged branch

⸻
13) Git commit logging (P65a, P99)
[ ] 13.1 Default ON (unless --no-git-logging)
[ ] 13.2 Spinup: git commit --allow-empty -m "WTX_SPINUP: branch=$BRANCH_NAME from=$FROM_REF"
[ ] 13.3 -c path: prior to send → git commit --allow-empty -m "WTX_COMMAND: $CMD" (sanitize: newline→space, length<=200, strip control)
[ ] 13.4 No additional commits for broadcast (post-commit already exists)
[ ] 13.5 Docs: warning about secrets (users expected not to put tokens in commits)
[ ] 13.6 Tests: with & without --no-git-logging counts

⸻
14) Concurrency cleanup (residual)
[ ] 14.1 prune lock (see 12.9)
[ ] 14.2 Numbering lock: detect stale (>30s) → warn and steal

⸻
15) Tests (augment existing) (P78–P81e)
[ ] 15.5 Ready flag: after spinup, tmux show-option returns 1 (retry logic)
[ ] 15.6 Prune dry-run vs real: assert no deletions w/ dry-run then real
[ ] 15.7 screen backend: run with MUX=screen minimal smoke (skip if screen absent)
[ ] 15.8 Attach-inside-tmux: switch-client behavior
[ ] 15.9 uv env created once (two branches)
[ ] 15.10 pnpm lockfile change triggers reinstall (touch lock)
[ ] 15.11 Messaging policies matrix + cycle injection
[ ] 15.12 Git logging commits count
[ ] 15.13 Branch name with slash & colon sanitized session name & preserved branch variable
[ ] 15.14 Invalid policy value → exit 64
[ ] 15.15 Performance smoke: 20 consecutive -c median < threshold (non-fatal if slow)

⸻
16) Docs (P83–P86b)
[ ] 16.1 README flags & env vars table (include hidden --_post-commit note for developers)
[ ] 16.2 Quickstart example block
[ ] 16.3 Security note (raw keystrokes + commit logging expectations)
[ ] 16.4 Troubleshooting list (sessions, orphan worktrees, GUI open failure)
[ ] 16.5 WTX_OPEN_STRATEGY documentation (planned)
[ ] 16.6 Messaging policy examples
[ ] 16.7 post-commit hook auto-install explanation & safe idempotence

⸻
17) Nits & polish
[ ] 17.2 Log chmod 700 (only first time) → detection via test -d + ! -f .perm_stamp
[ ] 17.3 Output normalization: each resource emits status created|reused|skipped|missing
[ ] 17.4 Performance timing instrumentation (P69–P71): record ms for phases (enable with --verbose)
[ ] 17.5 open=spawned|suppressed|failed token added to banner actions list (after GUI implemented)
[ ] 17.6 Deterministic banner ordering: env, pnpm, session, open, timing(optional)

⸻
Future (deferred features kept brief)
  • Close workflow (--close*, merge) — separate spec
  • GUI window spawn strategies (macOS AppleScript, iTerm2, kitty, etc.)
  • --debug verbose categories (timing, decisions)
  • Notifications (macOS / Linux)

⸻
End of remaining plan.

