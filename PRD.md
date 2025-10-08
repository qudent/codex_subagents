Perfect — you’re asking for the complete context + vision of wtx rewritten as a structured, fine-grained checklist where every single step or assumption is something that can be ticked off or verified during implementation or review.
Below is exactly that: a practical, readable “execution spec” for wtx, including both the intended behavior and the implementation checklist you can literally check box by box.

To agents working on this: Please write your notes BELOW each item, in the empty lines left for that.

⸻

✅ wtx Vision & Intended Usage (context checklist)

0. Purpose & concept

Point 1. [x] Goal: one command (wtx) to spin up, resume, and send live commands into self-contained branch workspaces (“living branches”).



Point 2. [x] Behavior: it creates a Git branch, worktree, and development shell (tmux or screen session) automatically.



Point 3. [x] Philosophy: each branch = its own living environment, always reproducible, instantly accessible, but sharing a single Python/JS environment for efficiency.



Point 4. [x] Primary audience: solo developers or small teams who iterate rapidly on multiple short-lived feature branches.



Point 5. [x] Outcome: typing




wtx feature-x -c "pytest -q"

creates or reuses everything and runs the command inside the right worktree/shell.

⸻

1. Invocation interface

Point 6. [ ] Command form: — Base flags supported; --close/--close-* remain TODO.



wtx [branch-name] [-c 'string'] [--no-open] [--mux tmux|screen] [--from REF] [--close|--close-merge|--close-force],
Point 7. [x] If branch-name omitted → autogenerate as wtx/<parent>-NN.



Point 8. [x] -c sends raw keystrokes to the session and presses Enter.



Point 9. [x] --mux selects backend (default: auto → prefer tmux).



Point 10. [x] --no-open suppresses GUI/OS-level terminal window spawning/focus logic (see GUI section); still prints attach command.



Point 11. [x] --from selects parent commit (defaults to current HEAD).



Point 12. [ ] --close will spin down that branch+worktree+tmux in the end/after this command is finished, aborting if there are uncommitted changes — Close workflow not implemented yet.



Point 13. [ ] --close-merge will commit, merge, then close — Close workflow not implemented yet.



Point 14. [ ] --close-force will spin down even with uncommitted changes — Close workflow not implemented yet.




Point 15. [ ] So to spin down a particular branch without command: wtx [branch-name] --close — Close workflow not implemented yet.



Point 16. [ ] to spin down the branch we are in now: wtx $(git rev-parse --abbrev-ref HEAD) --close — Close workflow not implemented yet.



wtx close [--force|--merge] [branch-name] spins down branch-name, deletes worktree, branch, tmux, branch-name, with [--merge] committing+merging everything into current branch, with [--force] closing even if there are uncommitted changes, without [branch-name] when run from a particular worktree/branch tmux it will finish this branch itself
⸻

2. Branch creation & metadata

Point 17. [x] Verify target branch exists; if not, create it from --from or current HEAD.



Point 18. [x] Save minimal metadata in branch description: — Also records from_ref for review context.




wtx: created_by=wtx
wtx: parent_branch=<name-or-none>

Point 19. [x] Do not store timestamps or SHA hashes.



Point 20. [x] Ensure branch description write is idempotent (re-runs don’t duplicate).



Point 21. [x] Keep this metadata human-readable (git config branch.<name>.description).



⸻

3. Worktree setup

Point 22. [x] Worktree path: ../<repo>.worktrees/<branch-name> relative to repo root.



Point 23. [x] If not present → git worktree add <path> <branch>.



Point 24. [x] If present → verify the path and branch match (idempotency).



Point 25. [x] Never touch untracked worktrees not created by wtx.



⸻

4. Environment policy

Point 26. [x] Python: use one shared uv environment (not per-worktree).



    Point 27. [x] Env path: $WTX_UV_ENV (default ~/.wtx/uv-shared).



    Point 28. [x] Create on first use: uv venv "$WTX_UV_ENV".



    Point 29. [x] Prepend "$WTX_UV_ENV/bin" to PATH for each session.



Point 30. [x] JavaScript: use pnpm.



    Point 31. [x] Run pnpm install --frozen-lockfile only if node_modules missing or lockfile changed.



    Point 32. [x] Rely on pnpm’s global store; never share node_modules directories.



Point 33. [x] All env operations must be idempotent (re-running wtx never damages an existing env).



⸻

5. Multiplexer session

Point 34. [x] Choose backend:



    Point 35. [x] tmux preferred; fallback to screen if tmux not installed.



Point 36. [x] Session name format: wtx:<repo-name>:<branch-name> (unique per repo). — Implemented with underscore separators to avoid tmux target parsing issues.



Point 37. [x] Create session rooted at the worktree:



    tmux → tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
    screen → screen -dmS "$SES_NAME" bash -c "cd '$WT_DIR'; exec bash".
Point 38. [x] Print a one-line banner inside the session:




wtx: repo=<repo> branch=<branch> parent=<parent> actions=[env, pnpm, ready]

Point 39. [x] Expose a tmux variable @wtx_ready=1 (or mark ready in screen) after shell init.



Point 40. [x] Re-use existing session if present.



Point 41. [x] Keep same naming to permit fast attach.



⸻

6. Input & live command sending

Point 42. [x] -c flag triggers raw keystroke send:



    tmux → tmux send-keys -t "$SES_NAME" "$CMD" C-m
    screen → screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
Point 43. [x] No parsing, no eval



Point 44. [x] If tmux session variable @wtx_ready absent → send anyway (raw).



Point 45. [ ] Confirm hot path completes in ≤25 ms on modern hardware. — Performance target not yet benchmarked.



⸻

7. GUI / OS-level window behavior (updated)

Point 46. [ ] On successful (create|reuse) if --no-open NOT set: spawn/focus a NEW terminal window (never hijack current terminal) using platform strategy: macOS (osascript Terminal / iTerm2 if available), Linux/X11 ($TERMINAL or x-terminal-emulator -e), Wayland (foot/kitty/alacritty fallback), else print attach instructions only.

    Point 46a. [ ] Strategy order configurable via env WTX_OPEN_STRATEGY (comma list: iterm,apple-terminal,kitty,alacritty,wezterm,gnome-terminal,foot,xterm,print). First succeeding command used.

    Point 46b. [ ] Each strategy launches a window already running `tmux attach -t <session>` (or screen -r) and foregrounds it.

Point 47. [x] --no-open means: do NOT spawn/focus any GUI window; always just print attach instructions to stdout (idempotent; safe in CI).

Point 48. [ ] If all spawn strategies fail → fall back to printing attach command (always printed anyway for scripting) and exit 0 (no hard failure).

Point 48a. [ ] Output explicitly states: open=spawned|suppressed|failed.

⸻

8. Messaging policy

Point 49. [ ] Environment variable WTX_MESSAGING_POLICY controls cross-session notices. Allowed values (simplified): all | parent | children | parent+children (default: parent+children). No other modes. Semantics:
    • parent: notify only the direct parent branch session (if it exists).
    • children: notify only immediate child branch sessions (those whose recorded parent_branch = current branch).
    • parent+children: union of parent and children (default practical collaboration mode).
    • all: every related session in the ancestry and descendant tree (transitive). Used mainly for broad broadcast (e.g. CI status) but may create more noise.

Point 50. [ ] On new commit or branch event → build message line (single echoable comment) with commit sha & subject (first line only).

# [wtx] <branch> commit <short-sha> "<subject>"

Point 51. [ ] Send this line (raw keystrokes) to each targeted session per policy via tmux send-keys / screen stuff.

Point 52. [ ] Message always begins with '# ' so it is a shell comment if surfaced in interactive history.

Point 53. [ ] No protocol / ack; best-effort fire-and-forget; failures (missing session) silently skipped (optionally logged with --debug later).

⸻

9. Prune command

Point 54. [ ] Command: wtx prune [--dry-run]. — prune command not implemented yet.



Point 55. [ ] Enumerate all worktrees and sessions. — prune command not implemented yet.



Point 56. [ ] For each: — prune command not implemented yet.



    Point 57. [ ] If worktree directory missing → kill session. — prune command not implemented yet.



    Point 58. [ ] If branch is wtx/* and fully merged → delete (unless --dry-run). — prune command not implemented yet.



    Point 59. [ ] Else leave intact. — prune command not implemented yet.



Point 60. [ ] Summarize deletions and skipped items. — prune command not implemented yet.



Point 61. [ ] Never touch non-wtx branches or worktrees. — prune command not implemented yet.



⸻

10. State & logs

Point 62. [x] All runtime data stored under $WTX_GIT_DIR/wtx/ inside .git:




$WTX_GIT_DIR/wtx/
  logs/
  locks/
  state/

Point 63. [x] Never write to working tree; never commit these files.



Point 64. [x] Always create dirs 700 permissions.



Point 65. [x] Log each command run with timestamp → $WTX_GIT_DIR/wtx/logs/YYYY-MM-DD.log.



⸻

11. Banner verification

Point 66. [x] When user attaches, first line printed should always show repo, branch, parent, parent commit (if detached) and summary of actions (linked, created, skipped, etc.).



Point 67. [x] Banner content comes from variables captured at runtime.



Point 68. [x] Verify in both tmux and screen modes.




⸻

12. Performance & idempotency

Point 69. [ ] Cold start: includes worktree add + pnpm install → seconds (depends on project). — Startup performance not yet profiled.



Point 70. [ ] Warm start: worktree and env exist → ≤400 ms. — Warm-start timing not yet measured.



Point 71. [ ] Hot path (-c send): ≤25 ms typical (tmux). — Hot-path timing not yet measured.



Point 72. [x] Re-running wtx multiple times should never duplicate branches or sessions.



Point 73. [ ] Output should clearly say whether each resource was created, reused, or skipped. — Need clearer stdout messaging about create/reuse outcomes.



Point 73a. [ ] Output includes open=spawned|suppressed|failed metric.

⸻

13. Testing & validation (expanded)

Point 74. [x] Create BATS or shell test suite.



Point 75. [x] Tests: — Automated via tests/wtx.bats.



    Point 76. [x] Auto-branch naming works sequentially.



    Point 77. [x] Worktree reuse idempotent.



    Point 78. [ ] Shared uv env detected/created once. — uv environment scenario not covered by tests.



    Point 79. [ ] pnpm install runs only on first spawn. — pnpm install scenario not covered by tests.



    Point 80. [x] -c command sends correctly (verify via tmux capture).



    Point 81. [ ] prune --dry-run lists expected items. — Prune flow absent, so no tests yet.



    Point 81a. [ ] Messaging policy tests: all, parent, children, parent+children — verify correct delivery set per policy.

    Point 81b. [ ] Recursive branch graph test: create depth ≥3; verify:
        • children: only level +1
        • parent: only direct parent
        • parent+children: union of above
        • all: reaches all ancestors & descendants without duplication.

    Point 81c. [ ] GUI spawn test (macOS mocked osascript & Linux fake $WTX_OPEN_STRATEGY) ensures open=spawned and suppressed.

    Point 81d. [ ] Attach suppression with --no-open prints attach command but does not spawn window (detect via mock).

Point 82. [x] Run tests for both tmux and screen backends.



⸻

14. Documentation & ergonomics

Point 83. [ ] Provide README section with example workflow: — README/docs still to be written.




# start new branch
wtx feature-x
# automatic new window attach (unless --no-open)
wtx feature-x -c 'pytest -q'
# open again later
wtx feature-x

Point 84. [ ] Explain environment variables (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY values: all|parent|children|parent+children, WTX_OPEN_STRATEGY).



Point 85. [ ] Clarify that raw keystrokes are unfiltered (behave like manual typing).



Point 86. [ ] Include troubleshooting: “session exists”, “worktree already exists”, GUI open failed (attach manually), etc.



Point 86a. [ ] Document WTX_OPEN_STRATEGY order and fallback behavior.

⸻

15. Future/optional features

Point 87. [ ] Add --debug flag for verbose logging. — Future enhancement.



Point 88. [ ] Add wtx attach alias for convenience. — Future enhancement.



Point 89. [ ] Add tab-completion script. — Future enhancement.



Point 90. [ ] Optionally integrate simple progress messages (spinner or [ok]). — Future enhancement.



Point 91. [ ] Optionally support wtx prune --delete-branches. — Future enhancement.



Point 91a. [ ] Optional: platform-specific fancy notification on spawn (macOS display notification, Linux notify-send) after environment ready.

⸻

16. Key design invariants

Point 92. [x] Everything runs within one repo; no cross-repo effects.



Point 93. [x] No background daemons.



Point 94. [x] All state ephemeral in .git/wtx/.



Point 95. [x] Shared uv env only; per-worktree envs discouraged.



Point 96. [x] tmux/screen abstraction minimal



Point 97. [x] Raw keystroke injection only; no FIFO protocol or auth overhead.



Point 98. [ ] Auto-open never blocks core logic; failures are soft; attach command always emitted.

⸻

✅ Result:
After every checklist item is implemented and ticked, the user experience is:

# create a new living branch environment
wtx
# new terminal window opens + attaches automatically (unless --no-open)
# see banner: wtx: repo=foo branch=wtx/main-003 parent=main actions=[env, pnpm:skipped, open:spawned]
# run code/tests
wtx -c "pytest"

All worktrees are in ../repo.worktrees/…, all state lives in .git/wtx/, and attaching to any branch instantly restores its environment. Attach instructions are always printed for scripting/CI (and indicate open=suppressed when --no-open used).


More additions/changes
<USER_FEEDBACK_TODO>
Point 99. [ ] By default, unless --no-git-logging is passed, we implement logging by empty git commit messages in branches for every passed by a wtx -c  invocation (git commit --allow-empty -m "WTX_COMMAND: <what the user instructed>" or "WTX_SPINUP: <if we spin up a new tree>)".README should briefly warn against copypasting secrets in that mode.

Point 100. [ ] the venv directory should be not global, but per repository (under GIT) at $(git rev-parse --git-common-dir)/../.venv