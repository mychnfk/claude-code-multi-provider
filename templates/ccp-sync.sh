#!/usr/bin/env bash
# ccp-sync — 公共配置层同步器
# 真相源: ~/.config/claude-pools/{common,third-party-common}.json + pools/<pool>.json
# 生成物: 各 CONFIG_DIR 的 settings.json(原子写,写前备份)
# 用法: ccp-sync [--check] [pool...]   默认全部四池;--check 只 diff 不写
#
# 源文件里的 __HOME__ 占位符在合并后统一替换为 $HOME(让模板可进版本库)。
# model 字段是 /model 命令持久化的运行时状态,故意不从源文件管理——sync 时从
# 现有落盘读回注入,避免冲掉用户的 /model 选择(坑 19)。
set -euo pipefail

SRC_DIR="$HOME/.config/claude-pools"
CHECK=0
POOLS=()

for arg in "$@"; do
  case "$arg" in
    --check|-n) CHECK=1 ;;
    *) POOLS+=("$arg") ;;
  esac
done
[[ ${#POOLS[@]} -eq 0 ]] && POOLS=(main glm kimi deepseek)

# jq 递归深合并:对象递归,其余(数组/标量)右侧覆盖。
# 注意必须 deepmerge($a;$b) 显式参数——reduce 内 . 被重绑定,deepmerge(a;b) 会产生 null。
DEEP_MERGE='
def deepmerge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce (($a | keys_unsorted) + ($b | keys_unsorted) | unique | .[]) as $k
      ({}; . + { ($k):
        if ($a | has($k)) and ($b | has($k)) then deepmerge($a[$k]; $b[$k])
        elif ($b | has($k)) then $b[$k]
        else $a[$k] end })
  else $b end;
'

sync_pool() {
  local pool="$1"
  local pfile="$SRC_DIR/pools/$pool.json"
  [[ -f "$pfile" ]] || { echo "✗ $pool: $pfile 不存在" >&2; return 1; }

  # 读元信息
  local target layers
  target=$(jq -r '._target' "$pfile")
  target="${target//__HOME__/$HOME}"
  layers=$(jq -r '._layers[]' "$pfile")

  # 组装合并输入: layers + 池文件(剥 _ 元键)
  local inputs=()
  for l in $layers; do
    [[ -f "$SRC_DIR/$l" ]] || { echo "✗ $pool: layer $l 缺失" >&2; return 1; }
    inputs+=("$SRC_DIR/$l")
  done
  inputs+=("$pfile")

  # 生成合并结果到临时文件
  local merged
  merged=$(mktemp /tmp/ccp-sync-XXXXXXXX)
  jq -s "$DEEP_MERGE"'
    (reduce .[] as $f ({}; deepmerge(.; $f)))
    | with_entries(select(.key | startswith("_") | not))
  ' "${inputs[@]}" > "$merged" || { rm -f "$merged"; echo "✗ $pool: 合并失败" >&2; return 1; }

  # 替换 __HOME__ 占位符为实际 $HOME(让模板可进版本库)
  python3 -c "
import json, sys, os
p = '$merged'
d = json.load(open(p))
def sub(o):
    if isinstance(o, dict): return {k: sub(v) for k, v in o.items()}
    if isinstance(o, list): return [sub(x) for x in o]
    if isinstance(o, str): return o.replace('__HOME__', os.environ['HOME'])
    return o
json.dump(sub(d), open(p, 'w'), indent=2, ensure_ascii=False)
" || { rm -f "$merged"; echo "✗ $pool: 占位符替换失败" >&2; return 1; }

  # 保留运行时状态: model 字段由 CC /model 命令持久化,sync 不覆盖——从现有落盘读回
  if [[ -f "$target" ]]; then
    local live_model
    live_model=$(jq -r '.model // empty' "$target" 2>/dev/null || true)
    if [[ -n "$live_model" ]]; then
      jq --arg m "$live_model" '.model = $m' "$merged" > "$merged.tmp" && mv "$merged.tmp" "$merged"
    fi
  fi

  # 校验 JSON 合法
  python3 -c "import json,sys; json.load(open('$merged'))" 2>/dev/null || {
    rm -f "$merged"; echo "✗ $pool: 合并结果 JSON 非法" >&2; return 1; }

  if [[ $CHECK -eq 1 ]]; then
    # 语义比较(排序键),忽略键序差异
    if [[ -f "$target" ]] && diff -q \
        <(python3 -c "import json; print(json.dumps(json.load(open('$target')),indent=1,sort_keys=True,ensure_ascii=False))") \
        <(python3 -c "import json; print(json.dumps(json.load(open('$merged')),indent=1,sort_keys=True,ensure_ascii=False))") >/dev/null 2>&1; then
      echo "✓ $pool: 无漂移"
    else
      echo "Δ $pool: 有差异 ($target)"
      diff \
        <(python3 -c "import json; print(json.dumps(json.load(open('$target')),indent=1,sort_keys=True,ensure_ascii=False))" 2>/dev/null || echo '{}') \
        <(python3 -c "import json; print(json.dumps(json.load(open('$merged')),indent=1,sort_keys=True,ensure_ascii=False))") | head -40 || true
    fi
    rm -f "$merged"
    return 0
  fi

  # 写前备份 + 原子写(目标目录可能不存在,先建)
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    cp "$target" "$target.bak-ccp-$(date +%Y%m%d-%H%M%S)"
  fi
  local tmp_target="$target.ccp-tmp"
  cp "$merged" "$tmp_target" && mv "$tmp_target" "$target" || { rm -f "$merged"; echo "✗ $pool: 写入失败" >&2; return 1; }
  rm -f "$merged"
  echo "✓ $pool: 已同步 → $target"
}

for p in "${POOLS[@]}"; do
  sync_pool "$p"
done
