**wtx TODO**

- Default parent branch for `wtx create` should be the current branch, not `main`.
  - Rationale: users expect a new attempt to branch from wherever they are working.
  - Plan:
    - Update `cmd_create` in `wtx` to set `parent` to the current branch by default (fallback to `main` if HEAD is detached).
    - Adjust tests in `test_wtx_flow.sh` to reflect new default.
    - Update README to remove the caveat once behavior changes.

