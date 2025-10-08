#!/usr/bin/env bats

load 'lib/wtx-helpers'

@test "messaging policy reaches parent and grandchildren" {
  export WTX_MESSAGING_POLICY="parent,children,grandchildren"
  run wtx --no-open
  [ "$status" -eq 0 ]
  parent_branch="wtx/main-1"
  parent_wt="$(actual_worktree_path "$parent_branch")"
  before_children=$(list_wtx_branches)
  run bash -c "cd $(printf %q "$parent_wt") && $(printf %q "$BATS_TEST_DIRNAME/../wtx") --no-open"
  [ "$status" -eq 0 ]
  after_children=$(list_wtx_branches)
  child_branch=$(first_new_branch "$before_children" "$after_children")
  [ -n "$child_branch" ]
  child_wt="$(actual_worktree_path "$child_branch")"
  before_grand=$(list_wtx_branches)
  run bash -c "cd $(printf %q "$child_wt") && $(printf %q "$BATS_TEST_DIRNAME/../wtx") --no-open"
  [ "$status" -eq 0 ]
  after_grand=$(list_wtx_branches)
  grand_branch=$(first_new_branch "$before_grand" "$after_grand")
  [ -n "$grand_branch" ]
  child_ses="$(session_name "$child_branch")"
  parent_ses="$(session_name "$parent_branch")"
  grand_ses="$(session_name "$grand_branch")"
  run wtx close --merge "$child_branch"
  [ "$status" -eq 0 ]
  sleep 1
  run tmux capture-pane -t "$parent_ses" -p
  [ "$status" -eq 0 ]
  parent_output="${output//$'\r'/}"
  parent_clean="${parent_output//[[:space:]]/}"
  parent_pattern="[wtx]merge$child_branch"
  [[ "$parent_clean" == *"$parent_pattern"* ]]
  run tmux capture-pane -t "$grand_ses" -p
  [ "$status" -eq 0 ]
  grand_output="${output//$'\r'/}"
  grand_clean="${grand_output//[[:space:]]/}"
  [[ "$grand_clean" == *"$parent_pattern"* ]]
  run tmux has-session -t "$child_ses" 2>/dev/null
  [ "$status" -ne 0 ]
}
