**wtx TODO (reconciled and simplified)**

Vision
- One terminal window per agent (tmux session). No in-place session switching.
- absolutely minimal functionality:
- "wtx create" adds worktree in git_root_dir/../<repo-name>.worktrees/<name>. Parent branch in branch description, "wtx add <name>" adds a specific name, if <name> not set, its a name derived from parent scheme + running counter. "wtx add <name> -c "<command>"" sends <command> and enter after spinning up. Spinning up involves linking .venv, source .venv/bin/activate, and pnpm install where applicable. tmux naming scheme reflects repo+branch name.
- "wtx message" messages according to WTX_MESSAGING_POLICY (default -- parent, children, possible: parents, children, all) about current commit, commit message, hash, precise command that target needs to enter to merge that commit.
- "empty git commit for sending messages and logging things without changing files (e.g. "NOTIF: ran tests")"
- "wtx prune" kills stale worktrees

You are absolutely right. My apologies for misreading the core purpose. If these are terminals for **coding agents**, then messaging isn't a feature—it's the central nervous system. Thank you for the clarification. That changes everything.

Let's put messaging back at the heart of the plan, but design it to be as simple and automatic as possible, based on your feedback.

---

### The New, Simplified Philosophy (Agent Edition)

**The Goal:** `wtx` is an orchestration tool for autonomous coding agents. It creates isolated environments and provides the primary communication channel (`wtx message`) for them to coordinate their work.

**The Mantra:** *Agents commit, and `wtx` tells the other agents what to do next.*

---

### The Radically Simplified `wtx message`

The complexity was in the options. Let's remove them. The command should have one job and do it well.

**The Command:**
```bash
wtx message
```

**What it Does (The Internal Logic):**
1.  **Identify Targets:** It automatically finds the parent branch (from the Git branch description) and all child branches (by scanning other branches' descriptions to see if they list the current branch as a parent).
2.  **Get Context:** It grabs the current commit hash (`HEAD`) and commit message.
3.  **Construct the Message:** It creates a clear, actionable message string.
    ```
    # [wtx from feature/auth]: new git commit with message: Update:... To integrate these changes, run: `git merge a1b2c3d`
    ```

    hashtag is important so that shell will parse it as comment. Newline only at the end.
4.  **Send via `tmux`:** For each target (parent and children), it finds the corresponding `tmux` session and uses `tmux send-keys` to type the entire message string into the terminal, followed by `Enter`.
`WTX_MESSAGING_POLICY="parent,children" wtx message` sends a message to parent, children (default). Default: messaging policy is "all".

**Key Simplifications:**
*   **No `--policy` flag.** The default, most useful behavior is to message both parents and children. This is what you want 99% of the time. We can add an env var `WTX_MESSAGING_POLICY` for power users later, but the base command has no options.
*   **No `--keys` flag.** As you said, it always sends keys. The option is redundant.
*   **The message includes the command.** This is critical. It's not just a notification; it explains what needs to be done.

---

### The Actionable Plan (Revised with Messaging)

The plan is still about ruthless prioritization, but now messaging is in the top tier.

#### **Phase 1: The Core Agent Loop**

1.  **`wtx create`:** (As before)
    *   Creates worktree and `tmux` session (branch is implicitly automatically created by git)
    ` "New commit made by worker in branch <branch>: $(git log -1 --pretty=%s). Merge by the following command: git merge <commit_hash>"`
    *   **NEW:** Installs a simple `post-commit` it hook into the new worktree. It looks like this:
        *   `.git/hooks/post-commit`:
            ```bash
            #!/bin/sh
            wtx message
            ```
        *   This makes messaging **automatic and effortless**. Every `git commit` triggers the communication.

2.  **`wtx list`:** (As before)
    *   git worktree list together with parent (from description, if exists), and whether it is "activated" with a corresponding tmux, and the name of that tmux. Contains instruction like "Enter worktree by tmux attach $(wtx worktree-to-tmux <path>)" or so.

3.  **`wtx message`:** (The New, Simplified Version)
    *   Implement the logic described above: find parent/children, construct message, `tmux send-keys`.
    *   This is the engine of the agent workflow.

4.  **`wtx prune`:** (As before)
    *   The cleanup hammer for stale worktrees.

**Result of Phase 1:** You now have a fully functional system for creating agents and having them automatically broadcast their progress to other relevant agents after every commit. This is a powerful and coherent workflow.

---

#### **Phase 2: Refinement and Cleanup**

1.  **`wtx finish`:** (Even more useful now)
    *   When an agent is done, a human (or a supervising agent) runs `wtx finish`.
    *   It prints something like "finishing" for the parent branch, deletes branch, prints merge command for commit hash
    *   It offers to `prune` the agent's worktree upon successful merge.

2.  **Environment Variables & Naming:** (As before)
    *   Standardize on `WTX_...`.
    *   Change session prefix to the repo name.

---

### Your New, Agent-Focused TODO List

**Phase 1: The Core Agent Loop**
- [ ] **Implement `wtx create <name>`**
    - [ ] Creates worktree, branch, and `tmux` session.
    - [ ] **Installs a `post-commit` hook** that automatically runs `wtx message`.
- [ ] **Implement `wtx message "<msg>"`**
    - [ ] Finds parent and child branches.
    - [ ] Constructs message with commit hash, commit message and merge command.
    - [ ] Uses `tmux send-keys` to inject the message into target sessions.
- [ ] **Implement `wtx list`** (as before)
- [ ] **Implement `wtx prune`** (as before)
- [ ] **Write a minimal README.md**
    - [ ] Document the agent workflow: `wtx create`, make changes, `git commit` (auto-messages), exiting tmux, `wtx prune`
    - [ ] Document `wtx list` as wrapper for `git worktree list`.

**Phase 2: Refinement**
- [ ] **Implement `wtx finish`**
- [ ] **Standardize Environment Vars & Naming**

This plan respects the core vision of an agent orchestration tool. It puts the most critical feature—messaging—front and center, but strips away the configuration complexity that bogged it down before. This feels like the right path.

install script/README should contain, so that tmuxes are more usable:
```
# Enable mouse support (scrolling, resizing, selecting panes)
set -g mouse on

# Large scrollback buffer
set -g history-limit 100000tmux source-file ~/.tmux.conf
```