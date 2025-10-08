Perfect — you’re asking for the complete context + vision of wtx rewritten as a structured, fine-grained checklist where every single step or assumption is something that can be ticked off or verified during implementation or review.
Below is exactly that: a practical, readable “execution spec” for wtx, including both the intended behavior and the implementation checklist you can literally check box by box.

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

Point 6. [x] Command form: — Base flags support close/merge/force toggles and existing mux/from options.



wtx [branch-name] [-c 'string'] [--no-open] [--mux tmux|screen] [--from REF] [--close|--close-merge|--close-force],
Point 7. [x] If branch-name omitted → autogenerate as wtx/<parent>-NN.



Point 8. [x] -c sends raw keystrokes to the session and presses Enter.



Point 9. [x] --mux selects backend (default: auto → prefer tmux).



Point 10. [x] --no-open suppresses GUI/OS-level terminal window spawning/focus logic while still printing an attach command for manual use.



Point 11. [x] --from selects parent commit (defaults to current HEAD).




Point 12. [x] --close will spin down that branch+worktree+tmux in the end/after this command is finished, aborting if there are uncommitted changes — Implemented via CLOSE_AFTER path (soft mode).



Point 13. [x] --close-merge will commit, merge, then close — Implemented via close_branch_command with auto-commit + parent merge before cleanup.



Point 14. [x] --close-force will spin down even with uncommitted changes — Implemented via close_branch_command force path.




Point 15. [x] So to spin down a particular branch without command: wtx [branch-name] --close — Supported by --close-* flags on primary invocation.



Point 16. [x] to spin down the branch we are in now: wtx $(git rev-parse --abbrev-ref HEAD) --close — Implemented via wtx close [BRANCH] defaulting to current branch.




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

7. GUI behavior

Point 46. [x] If --no-open not set: — Implemented via try_gui_attach helper with tmux/screen fallbacks.



    Point 47. [x] Try to focus/open a GUI terminal attached to the session — AppleScript, $WTX_TERMINAL, and x-terminal-emulator fallbacks wired through try_gui_attach.



        macOS → AppleScript tell app "Terminal" to do script "tmux attach -t $SES"
        Linux → $TERMINAL -e "tmux attach -t $SES".
Point 48. [x] If focusing fails → print the attach command for manual use. — Scripts now emit attach command only when GUI launch fails or --no-open set.




⸻

8. Messaging policy

Point 49. [ ] Environment variable WTX_MESSAGING_POLICY controls cross-session notices. — Only a broadcast/none toggle is wired (WTX_MESSAGING_POLICY=none disables messaging); parent/children targeting still pending.



Point 50. [x] On new commit or branch event → build message: — Implemented via send_repo_message hooks for auto-commit and merge events.




# [wtx] on <branch>: commit <sha> "<msg>" — merge: git merge <sha>

Point 51. [x] Send this line as raw keystrokes to targeted sessions (tmux/screen). — tmux/send-keys and screen stuff pipelines now deliver the comment.



Point 52. [x] Ensure it’s commented (#) so it’s safe if pasted in shell. — Messages prefixed with "# [wtx]".



Point 53. [x] No complex protocol — Simple broadcast loop over repo-tagged sessions.




⸻

9. Prune command

Point 54. [x] Command: wtx prune [--dry-run]. — Implemented with dry-run reporting and optional deletion.



Point 55. [x] Enumerate all worktrees and sessions. — prune_command walks tmux, screen, and worktree listings.



Point 56. [x] For each: — prune_command inspects orphaned sessions and merged branches.



    Point 57. [x] If worktree directory missing → kill session. — Implemented for tmux/screen sessions (respects --dry-run).



    Point 58. [x] If branch is wtx/* and fully merged → delete (unless --dry-run). — Implemented behind --delete-branches flag.



    Point 59. [x] Else leave intact. — Non-matching branches and tracked worktrees skipped.



Point 60. [x] Summarize deletions and skipped items. — prune_command prints report lines and completion message.



Point 61. [x] Never touch non-wtx branches or worktrees. — Filters by prefixed state and repo id.




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

Point 66. [x] When user attaches, first line printed should always show repo, branch, parent, and summary of actions (linked, created, skipped, etc.).



Point 67. [x] Banner content comes from variables captured at runtime.



Point 68. [x] Verify in both tmux and screen modes.




⸻

12. Performance & idempotency

Point 69. [ ] Cold start: includes worktree add + pnpm install → seconds (depends on project). — Startup performance not yet profiled.



Point 70. [ ] Warm start: worktree and env exist → ≤400 ms. — Warm-start timing not yet measured.



Point 71. [ ] Hot path (-c send): ≤25 ms typical (tmux). — Hot-path timing not yet measured.



Point 72. [x] Re-running wtx multiple times should never duplicate branches or sessions.



Point 73. [ ] Output should clearly say whether each resource was created, reused, or skipped. — Need clearer stdout messaging about create/reuse outcomes.




⸻

13. Testing & validation

Point 74. [x] Create BATS or shell test suite.



Point 75. [x] Tests: — Automated via tests/wtx.bats.



    Point 76. [x] Auto-branch naming works sequentially.



    Point 77. [x] Worktree reuse idempotent.



    Point 78. [ ] Shared uv env detected/created once. — uv environment scenario not covered by tests.



    Point 79. [ ] pnpm install runs only on first spawn. — pnpm install scenario not covered by tests.



    Point 80. [x] -c command sends correctly (verify via tmux capture).



    Point 81. [x] prune --dry-run lists expected items. — bats suite covers dry-run output.



Point 82. [x] Run tests for both tmux and screen backends.




⸻

14. Documentation & ergonomics

Point 83. [ ] Provide README section with example workflow: — README/docs still to be written.




# start new branch
wtx feature-x
# run quick test
wtx feature-x -c 'pytest -q'
# open again later
wtx feature-x

Point 84. [ ] Explain environment variables (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY). — Environment variable documentation pending.



Point 85. [ ] Clarify that raw keystrokes are unfiltered (behave like manual typing). — Raw keystroke behavior not documented yet.



Point 86. [ ] Include troubleshooting: “session exists”, “worktree already exists”, etc. — Troubleshooting section pending.




⸻

15. Future/optional features

Point 87. [ ] Add --debug flag for verbose logging. — Future enhancement.



Point 88. [ ] Add wtx attach alias for convenience. — Future enhancement.



Point 89. [ ] Add tab-completion script. — Future enhancement.



Point 90. [ ] Optionally integrate simple progress messages (spinner or [ok]). — Future enhancement.



Point 91. [x] Optionally support wtx prune --delete-branches. — Implemented flag removes merged wtx/* branches when requested.




⸻

16. Key design invariants

Point 92. [x] Everything runs within one repo; no cross-repo effects.



Point 93. [x] No background daemons.



Point 94. [x] All state ephemeral in .git/wtx/.



Point 95. [x] Shared uv env only; per-worktree envs discouraged.



Point 96. [x] tmux/screen abstraction minimal



Point 97. [x] Raw keystroke injection only; no FIFO protocol or auth overhead.




⸻

✅ Result:
After every checklist item is implemented and ticked, the user experience is:

# create a new living branch environment
wtx
# attach automatically
# see banner: wtx: repo=foo branch=wtx/main-003 parent=main actions=[env, pnpm:skipped]
# run code/tests
wtx -c "pytest"

All worktrees are in ../repo.worktrees/…, all state lives in .git/wtx/, and attaching to any branch instantly restores its environment.
