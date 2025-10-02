**wtx TODO**

- Default parent branch for `wtx create` should be the current branch, not `main`.
  - Status (2025-10-02): Not started — 0/3 tasks complete. Current behavior is still defaulting to `main` and tests/README reflect that.
  - Rationale: users expect a new attempt to branch from wherever they are working.
  - Plan (checkbox = done):
    - [ ] Update `cmd_create` in `wtx` to set the default `parent` to the current branch (fallback to `main` if HEAD is detached).
    - [ ] Adjust tests in `test_wtx_flow.sh` to reflect the new default.
    - [ ] Update README to remove the “heads‑up” caveat once behavior changes.

