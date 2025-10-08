# messaging policy helpers

wtx_policy_parse() {
  raw=$(printf '%s' "${WTX_MESSAGING_POLICY:-parent,children}" | tr 'A-Z ' 'a-z,')
  raw=$(printf '%s' "$raw" | sed 's/,,*/,/g; s/^,//; s/,$//')
  POLICY_TOKENS=",$raw,"
  case "$raw" in
    ''|none) WTX_POLICY_MODE=none; return ;;
  esac
  case ",$raw," in
    *,all,*) WTX_POLICY_MODE=all ;;
    *) WTX_POLICY_MODE=targeted ;;
  esac
}

wtx_policy_enabled() {
  token="$1"
  case "$POLICY_TOKENS" in
    *,$token,*) return 0 ;;
  esac
  return 1
}

wtx_messaging_build_graph() {
  graph=$(mktemp "$WTX_GIT_DIR_ABS/tmp.graph.XXXXXX")
  for file in "$WTX_GIT_DIR_ABS"/state/*.json; do
    [ -f "$file" ] || continue
    branch=$(wtx_read_state_field "$file" branch_name)
    parent=$(wtx_read_state_field "$file" parent_branch)
    [ -n "$branch" ] || continue
    printf '%s\t%s\n' "$branch" "$parent" >>"$graph"
  done
  printf '%s' "$graph"
}

wtx_messaging_children_of() {
  branch="$1"; graph="$2"
  awk -F '\t' -v parent="$branch" '$2==parent {print $1}' "$graph"
}

wtx_messaging_send_to_branch() {
  branch="$1"; message="$2"
  [ -n "$branch" ] || return
  session=$(wtx_session_name_for_branch "$branch")
  if need tmux && tmux has-session -t "$session" 2>/dev/null; then
    repo_tag=$(wtx_tmux_repo_match "$session")
    if [ -z "$repo_tag" ] || [ "$repo_tag" = "$REPO_ID" ]; then
      tmux send-keys -t "$session" "$message" C-m
    fi
  fi
  if need screen && screen -ls 2>/dev/null | grep -q "\.${session}[[:space:]]"; then
    screen -S "$session" -p 0 -X stuff "$message$(printf '\r')"
  fi
}

wtx_messaging_send_all() {
  message="$1"
  if need tmux; then
    tmux_lines=$(tmux list-sessions -F '#{session_name} #{@wtx_repo_id}' 2>/dev/null || true)
    OLDIFS="$IFS"; IFS=$'\n'
    for line in $tmux_lines; do
      sess=$(printf '%s' "$line" | awk '{print $1}')
      repo_id=$(printf '%s' "$line" | awk '{print $2}')
      [ -n "$sess" ] || continue
      [ "$repo_id" = "$REPO_ID" ] || continue
      tmux send-keys -t "$sess" "$message" C-m
    done
    IFS="$OLDIFS"
  fi
  if need screen; then
    screen_lines=$(screen -ls 2>/dev/null | awk '/\t/ {print $1}' || true)
    prefix="wtx_${SANITIZED_REPO}_"
    OLDIFS="$IFS"; IFS=$'\n'
    for entry in $screen_lines; do
      session=${entry#*.}
      case "$session" in
        ${prefix}*) screen -S "$session" -p 0 -X stuff "$message$(printf '\r')" 2>/dev/null || true ;;
      esac
    done
    IFS="$OLDIFS"
  fi
}

wtx_send_repo_message() {
  branch="$1"; message="$2"
  [ -n "$message" ] || return
  wtx_policy_parse
  case "$WTX_POLICY_MODE" in
    none) return ;;
    all) wtx_messaging_send_all "$message"; return ;;
  esac

  graph=$(wtx_messaging_build_graph)
  targets=""
  if wtx_policy_enabled self; then
    targets="$branch"
  fi
  if wtx_policy_enabled parent; then
    parent=$(wtx_parent_for_branch "$branch")
    if [ -n "$parent" ] && [ "$parent" != "detached" ] && [ "$parent" != "HEAD" ]; then
      targets=$(printf '%s\n%s' "$targets" "$parent")
    fi
  fi
  if wtx_policy_enabled children; then
    children=$(wtx_messaging_children_of "$branch" "$graph")
    if [ -n "$children" ]; then
      targets=$(printf '%s\n%s' "$targets" "$children")
    fi
    parent_for_siblings=$(wtx_parent_for_branch "$branch")
    if [ -n "$parent_for_siblings" ]; then
      siblings=$(wtx_messaging_children_of "$parent_for_siblings" "$graph")
      if [ -n "$siblings" ]; then
        OLDIFS="$IFS"; IFS=$'\n'
        for sib in $siblings; do
          [ -n "$sib" ] || continue
          [ "$sib" = "$branch" ] && continue
          targets=$(printf '%s\n%s' "$targets" "$sib")
        done
        IFS="$OLDIFS"
      fi
    fi
  fi
  if wtx_policy_enabled grandchildren; then
    kids=$(wtx_messaging_children_of "$branch" "$graph")
    OLDIFS="$IFS"; IFS=$'\n'
    for child in $kids; do
      [ -n "$child" ] || continue
      grand=$(wtx_messaging_children_of "$child" "$graph")
      if [ -n "$grand" ]; then
        targets=$(printf '%s\n%s' "$targets" "$grand")
      fi
    done
    IFS="$OLDIFS"
  fi

  printf '%s' "$targets" | sed '/^$/d' | sort -u | while IFS= read -r target; do
    wtx_messaging_send_to_branch "$target" "$message"
  done
  rm -f "$graph"
}
