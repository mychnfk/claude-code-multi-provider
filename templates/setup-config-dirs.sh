#!/usr/bin/env bash
# claude-code-multi-provider v2:初始化各供应商的 CLAUDE_CONFIG_DIR
# 做四件事:建目录 + symlink 共享层(plugins/skills/memory) + 迁移 enabledPlugins 等体验键 + 放置 settings.json
# 幂等,重复跑无害。用法: bash setup-config-dirs.sh
set -euo pipefail

MAIN_DIR="${HOME}/.claude"
HERE="$(cd "$(dirname "$0")" && pwd)"
PROVIDERS=(glm kimi deepseek)
# 常用工作目录(相对 ~/.claude/projects/ 的命名),memory 共享用;新目录首会话后自行补链
MEMORY_CWDS=("-Users-${USER}" "-Users-${USER}-sub2api")

for p in "${PROVIDERS[@]}"; do
    D="${HOME}/.claude-${p}"
    mkdir -p "${D}/projects"

    # 共享层:插件与技能 symlink 到主位
    ln -sfn "${MAIN_DIR}/plugins" "${D}/plugins"
    ln -sfn "${MAIN_DIR}/skills"  "${D}/skills"

    # 记忆共享:逐工作目录 symlink memory
    for cwd in "${MEMORY_CWDS[@]}"; do
        if [[ -d "${MAIN_DIR}/projects/${cwd}/memory" ]]; then
            mkdir -p "${D}/projects/${cwd}"
            ln -sfn "${MAIN_DIR}/projects/${cwd}/memory" "${D}/projects/${cwd}/memory"
        fi
    done

    # settings.json:模板就位;已存在则只补 enabledPlugins/statusLine/hooks/theme 等体验键
    if [[ ! -f "${D}/settings.json" && -f "${HERE}/settings-${p}.json" ]]; then
        cp "${HERE}/settings-${p}.json" "${D}/settings.json"
    fi
    python3 - "$MAIN_DIR" "$D" <<'PYEOF'
import json, sys
main_dir, d = sys.argv[1], sys.argv[2]
try:
    main = json.load(open(f'{main_dir}/settings.json'))
except FileNotFoundError:
    sys.exit(0)
carry = {k: main[k] for k in ['enabledPlugins','statusLine','hooks','editorMode','theme','autoCompactEnabled'] if k in main}
if not carry:
    sys.exit(0)
try:
    mine = json.load(open(f'{d}/settings.json'))
except FileNotFoundError:
    mine = {}
mine.update(carry)
json.dump(mine, open(f'{d}/settings.json','w'), indent=2, ensure_ascii=False)
PYEOF

    echo "[ok] ${D}"
done

echo "done. 下一步: templates/zsh-functions.zsh 放进 shell 启动文件,key 存 Keychain"
