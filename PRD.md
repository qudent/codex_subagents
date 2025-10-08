Perfect — you’re asking for the complete context + vision of wtx rewritten as a structured, fine-grained checklist where every single step or assumption is something that can be ticked off or verified during implementation or review.
Below is exactly that: a practical, readable “execution spec” for wtx, including both the intended behavior and the implementation checklist you can literally check box by box.

⸻

✅ wtx Vision & Intended Usage (context checklist)

0. Purpose & concept

Point 1. [ ] Goal: one command (wtx) to spin up, resume, and send live commands into self-contained branch workspaces (“living branches”).



Point 2. [ ] Behavior: it creates a Git branch, worktree, and development shell (tmux or screen session) automatically.



Point 3. [ ] Philosophy: each branch = its own living environment, always reproducible, instantly accessible, but sharing a single Python/JS environment for efficiency.



Point 4. [ ] Primary audience: solo developers or small teams who iterate rapidly on multiple short-lived feature branches.



Point 5. [ ] Outcome: typing




wtx feature-x -c "pytest -q"

creates or reuses everything and runs the command inside the right worktree/shell.

⸻

1. Invocation interface

Point 6. [ ] Command form:



wtx [branch-name] [-c 'string'] [--no-open] [--mux tmux|screen] [--from REF] [--close|--close-merge|--close-force],
Point 7. [ ] If branch-name omitted → autogenerate as wtx/<parent>-NN.



Point 8. [ ] -c sends raw keystrokes to the session and presses Enter.



Point 9. [ ] --mux selects backend (default: auto → prefer tmux).



Point 10. [ ] --no-open suppresses GUI terminal focus.



Point 11. [ ] --from selects parent commit (defaults to current HEAD).




Point 12. [ ] --close will spin down that branch+worktree+tmux in the end/after this command is finished, aborting if there are uncommitted changes



Point 13. [ ] --close-merge will commit, merge, then close



Point 14. [ ] --close-force will spin down even with uncommitted changes




Point 15. [ ] So to spin down a particular branch without command: wtx [branch-name] --close



Point 16. [ ] to spin down the branch we are in now: wtx $(git rev-parse --abbrev-ref HEAD) --close




wtx close [--force|--merge] [branch-name] spins down branch-name, deletes worktree, branch, tmux, branch-name, with [--merge] committing+merging everything into current branch, with [--force] closing even if there are uncommitted changes, without [branch-name] when run from a particular worktree/branch tmux it will finish this branch itself
⸻

2. Branch creation & metadata

Point 17. [ ] Verify target branch exists; if not, create it from --from or current HEAD.



Point 18. [ ] Save minimal metadata in branch description:




wtx: created_by=wtx
wtx: parent_branch=<name-or-none>

Point 19. [ ] Do not store timestamps or SHA hashes.



Point 20. [ ] Ensure branch description write is idempotent (re-runs don’t duplicate).



Point 21. [ ] Keep this metadata human-readable (git config branch.<name>.description).




⸻

3. Worktree setup

Point 22. [ ] Worktree path: ../<repo>.worktrees/<branch-name> relative to repo root.



Point 23. [ ] If not present → git worktree add <path> <branch>.



Point 24. [ ] If present → verify the path and branch match (idempotency).



Point 25. [ ] Never touch untracked worktrees not created by wtx.




⸻

4. Environment policy

Point 26. [ ] Python: use one shared uv environment (not per-worktree).



    Point 27. [ ] Env path: $WTX_UV_ENV (default ~/.wtx/uv-shared).



    Point 28. [ ] Create on first use: uv venv "$WTX_UV_ENV".



    Point 29. [ ] Prepend "$WTX_UV_ENV/bin" to PATH for each session.



Point 30. [ ] JavaScript: use pnpm.



    Point 31. [ ] Run pnpm install --frozen-lockfile only if node_modules missing or lockfile changed.



    Point 32. [ ] Rely on pnpm’s global store; never share node_modules directories.



Point 33. [ ] [ ] All env operations must be idempotent (re-running wtx never damages an existing env).




⸻

5. Multiplexer session

Point 34. [ ] Choose backend:



    Point 35. [ ] tmux preferred; fallback to screen if tmux not installed.



Point 36. [ ] Session name format: wtx:<repo-name>:<branch-name> (unique per repo).



Point 37. [ ] Create session rooted at the worktree:



    tmux → tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
    screen → screen -dmS "$SES_NAME" bash -c "cd '$WT_DIR'; exec bash".
Point 38. [ ] Print a one-line banner inside the session:




wtx: repo=<repo> branch=<branch> parent=<parent> actions=[env, pnpm, ready]

Point 39. [ ] Expose a tmux variable @wtx_ready=1 (or mark ready in screen) after shell init.



Point 40. [ ] Re-use existing session if present.



Point 41. [ ] Keep same naming to permit fast attach.




⸻

6. Input & live command sending

Point 42. [ ] -c flag triggers raw keystroke send:



    tmux → tmux send-keys -t "$SES_NAME" "$CMD" C-m
    screen → screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
Point 43. [ ] No parsing, no eval — send literally as if typed by user.



Point 44. [ ] If tmux session variable @wtx_ready absent → send anyway (raw).



Point 45. [ ] Confirm hot path completes in ≤25 ms on modern hardware.




⸻

7. GUI behavior

Point 46. [ ] If --no-open not set:



    Point 47. [ ] Try to focus/open a GUI terminal attached to the session



        macOS → AppleScript tell app "Terminal" to do script "tmux attach -t $SES"
        Linux → $TERMINAL -e "tmux attach -t $SES".
Point 48. [ ] If focusing fails → print the attach command for manual use.




⸻

8. Messaging policy

Point 49. [ ] Environment variable WTX_MESSAGING_POLICY controls cross-session notices (parent,children default).



Point 50. [ ] On new commit or branch event → build message:




# [wtx] on <branch>: commit <sha> "<msg>" — merge: git merge <sha>

Point 51. [ ] Send this line as raw keystrokes to targeted sessions (tmux/screen).



Point 52. [ ] Ensure it’s commented (#) so it’s safe if pasted in shell.



Point 53. [ ] No complex protocol — just informative notifications.




⸻

9. Prune command

Point 54. [ ] Command: wtx prune [--dry-run].



Point 55. [ ] Enumerate all worktrees and sessions.



Point 56. [ ] For each:



    Point 57. [ ] If worktree directory missing → kill session.



    Point 58. [ ] If branch is wtx/* and fully merged → delete (unless --dry-run).



    Point 59. [ ] Else leave intact.



Point 60. [ ] Summarize deletions and skipped items.



Point 61. [ ] Never touch non-wtx branches or worktrees.




⸻

10. State & logs

Point 62. [ ] All runtime data stored under $WTX_GIT_DIR/wtx/ inside .git:




$WTX_GIT_DIR/wtx/
  logs/
  locks/
  state/

Point 63. [ ] Never write to working tree; never commit these files.



Point 64. [ ] Always create dirs 700 permissions.



Point 65. [ ] Log each command run with timestamp → $WTX_GIT_DIR/wtx/logs/YYYY-MM-DD.log.




⸻

11. Banner verification

Point 66. [ ] When user attaches, first line printed should always show repo, branch, parent, and summary of actions (linked, created, skipped, etc.).



Point 67. [ ] Banner content comes from variables captured at runtime.



Point 68. [ ] Verify in both tmux and screen modes.




⸻

12. Performance & idempotency

Point 69. [ ] Cold start: includes worktree add + pnpm install → seconds (depends on project).



Point 70. [ ] Warm start: worktree and env exist → ≤400 ms.



Point 71. [ ] Hot path (-c send): ≤25 ms typical (tmux).



Point 72. [ ] Re-running wtx multiple times should never duplicate branches or sessions.



Point 73. [ ] Output should clearly say whether each resource was created, reused, or skipped.




⸻

13. Testing & validation

Point 74. [ ] Create BATS or shell test suite.



Point 75. [ ] Tests:



    Point 76. [ ] Auto-branch naming works sequentially.



    Point 77. [ ] Worktree reuse idempotent.



    Point 78. [ ] Shared uv env detected/created once.



    Point 79. [ ] pnpm install runs only on first spawn.



    Point 80. [ ] -c command sends correctly (verify via tmux capture).



    Point 81. [ ] prune --dry-run lists expected items.



Point 82. [ ] Run tests for both tmux and screen backends.




⸻

14. Documentation & ergonomics

Point 83. [ ] Provide README section with example workflow:




# start new branch
wtx feature-x
# run quick test
wtx feature-x -c 'pytest -q'
# open again later
wtx feature-x

Point 84. [ ] Explain environment variables (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY).



Point 85. [ ] Clarify that raw keystrokes are unfiltered (behave like manual typing).



Point 86. [ ] Include troubleshooting: “session exists”, “worktree already exists”, etc.




⸻

15. Future/optional features

Point 87. [ ] Add --debug flag for verbose logging.



Point 88. [ ] Add wtx attach alias for convenience.



Point 89. [ ] Add tab-completion script.



Point 90. [ ] Optionally integrate simple progress messages (spinner or [ok]).



Point 91. [ ] Optionally support wtx prune --delete-branches.




⸻

16. Key design invariants

Point 92. [ ] Everything runs within one repo; no cross-repo effects.



Point 93. [ ] No background daemons.



Point 94. [ ] All state ephemeral in .git/wtx/.



Point 95. [ ] Shared uv env only; per-worktree envs discouraged.



Point 96. [ ] tmux/screen abstraction minimal—no feature loss if one missing.



Point 97. [ ] Raw keystroke injection only; no FIFO protocol or auth overhead.




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
