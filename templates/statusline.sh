#!/bin/bash
# Claude Code status line(带池名前缀)
# 读取 stdin JSON,输出:[池名] 模型名 | 上下文占用 | 目录名
# 池名从 $CLAUDE_CONFIG_DIR 提取(CC 主进程 env,statusline 子进程继承):
#   空/~/.claude=main,否则取 .claude- 后缀(glm/kimi/deepseek)
# 用法: 放到 ~/.claude/statusline.sh,settings.json 的 statusLine.command 指向它

input=$(cat)

# 池名提取
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
case "$CFG_DIR" in
  "$HOME/.claude") POOL="main" ;;
  "$HOME"/.claude-*) POOL="${CFG_DIR##*/.claude-}" ;;
  *) POOL=$(basename "$CFG_DIR") ;;
esac

if command -v jq >/dev/null 2>&1; then
  MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
  USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
  CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
  IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
  DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
else
  MODEL=$(echo "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("model",{}).get("display_name","unknown"))')
  USED_PCT=$(echo "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("context_window",{}).get("used_percentage"); print(v if v is not None else "")')
  CTX_SIZE=$(echo "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("context_window",{}).get("context_window_size"); print(v if v is not None else "")')
  IN_TOK=$(echo "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("context_window",{}).get("total_input_tokens"); print(v if v is not None else "")')
  DIR=$(echo "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); w=d.get("workspace",{}) or {}; print(w.get("current_dir") or d.get("cwd") or "")')
fi

# ANSI 颜色(暗色适配终端 dim 主题)
RESET="\033[0m"
MODEL_COLOR="\033[2;36m"   # dim cyan
DIR_COLOR="\033[2;90m"     # dim gray
POOL_COLOR="\033[2;35m"    # dim magenta

# 已用 token 数:与 used_percentage 口径一致,只算输入侧(含 cache 读写),不含 output
USED_TOK="$IN_TOK"

# 格式化 token 数为 k/M 单位
fmt_k() {
  local n=$1
  if [ -z "$n" ]; then
    echo ""
  elif [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}' | sed 's/\.0M/M/'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.0fk", n/1000}'
  else
    echo "$n"
  fi
}

CTX_STR=""
if [ -n "$USED_PCT" ]; then
  PCT_INT=$(awk -v p="$USED_PCT" 'BEGIN{printf "%.0f", p}')
  if [ "$PCT_INT" -lt 50 ]; then
    PCT_COLOR="\033[2;32m"   # dim green
  elif [ "$PCT_INT" -lt 80 ]; then
    PCT_COLOR="\033[2;33m"   # dim yellow
  else
    PCT_COLOR="\033[2;31m"   # dim red
  fi

  if [ -n "$USED_TOK" ] && [ -n "$CTX_SIZE" ]; then
    CTX_STR=$(printf "${PCT_COLOR}%s%%%s (%s/%s)${RESET}" "$PCT_INT" "" "$(fmt_k "$USED_TOK")" "$(fmt_k "$CTX_SIZE")")
  else
    CTX_STR=$(printf "${PCT_COLOR}%s%%${RESET}" "$PCT_INT")
  fi
fi

DIR_STR=""
if [ -n "$DIR" ]; then
  BASE=$(basename "$DIR")
  DIR_STR=$(printf "${DIR_COLOR}%s${RESET}" "$BASE")
fi

POOL_STR=$(printf "${POOL_COLOR}[%s]${RESET}" "$POOL")
OUT=$(printf "%s ${MODEL_COLOR}%s${RESET}" "$POOL_STR" "$MODEL")
[ -n "$CTX_STR" ] && OUT="$OUT | $CTX_STR"
[ -n "$DIR_STR" ] && OUT="$OUT | $DIR_STR"

printf "%b\n" "$OUT"
