#!/bin/bash
# Installs the Claude Code statusLine hook that feeds ClaudeUsageBar.
# Safe to re-run: merges into settings.json, never overwrites unrelated keys.
set -e

CLAUDE_DIR="$HOME/.claude"
HOOK="$CLAUDE_DIR/hooks/usage-snapshot.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found. It ships with recent macOS; otherwise: brew install jq" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR/hooks"

cat > "$HOOK" <<'HOOKEOF'
#!/bin/bash
# Statusline command: captures Claude subscription usage windows to a JSON file,
# then prints a short status string.
SNAPSHOT="$HOME/.claude/usage-snapshot.json"
TMP="$SNAPSHOT.$$.tmp"
input=$(cat)

# Claude Code omits rate_limits until the session's first API response; keep the last good snapshot.
has_limits=$(echo "$input" | jq -r 'if (.rate_limits.five_hour // .rate_limits.seven_day) then "yes" else "" end' 2>/dev/null)
[ -n "$has_limits" ] && echo "$input" | jq -c '{
  captured_at: (now | floor),
  five_hour: (.rate_limits.five_hour // null),
  seven_day: (.rate_limits.seven_day // null),
  spend_limit: (.rate_limits.spend_limit // null),
  context_used_pct: (.context_window.used_percentage // null)
}' > "$TMP" 2>/dev/null && mv "$TMP" "$SNAPSHOT" || rm -f "$TMP"

five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
out=""
[ -n "$five" ] && out="5h $(printf '%.0f' "$five")%"
[ -n "$week" ] && out="$out | 7d $(printf '%.0f' "$week")%"
[ -z "$out" ] && out="usage n/a"
echo "$out"
HOOKEOF

chmod +x "$HOOK"
echo "installed hook: $HOOK"

if [ -f "$SETTINGS" ]; then
  EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "$HOOK" ]; then
    echo "warning: settings.json already has a different statusLine:" >&2
    echo "  $EXISTING" >&2
    echo "Leaving it alone. Merge manually if you want both." >&2
    exit 1
  fi
  BACKUP="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  NOTE="  (backup: $BACKUP)"
else
  echo '{}' > "$SETTINGS"
  NOTE=""
fi

jq --arg cmd "$HOOK" '. + {statusLine: {type: "command", command: $cmd}}' "$SETTINGS" > "$SETTINGS.tmp" \
  && jq empty "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS"

echo "wired statusLine in: $SETTINGS$NOTE"
echo
echo "Done. Open Claude Code CLI once, then ClaudeUsageBar will show live numbers."
