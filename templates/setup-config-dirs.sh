#!/usr/bin/env bash
# claude-code-multi-provider v2.4:初始化各供应商的 CLAUDE_CONFIG_DIR
# 做四件事:建目录 + symlink 共享层(plugins/skills/会话池) + 迁移 enabledPlugins 等体验键 + 放置 settings.json
# v2.4 起共享层含 projects/file-history/session-env(会话池),四入口可跨供应商 --resume;
# memory 随共享的 projects 自动共享,不再需要逐工作目录补链。
# 已有存量会话数据的目录不会被动,请跑 templates/share-session-pool.sh 迁移。
# 幂等,重复跑无害。用法: bash setup-config-dirs.sh
set -euo pipefail

MAIN_DIR="${HOME}/.claude"
HERE="$(cd "$(dirname "$0")" && pwd)"
PROVIDERS=(glm kimi deepseek)

# 主位共享目录兜底创建
mkdir -p "${MAIN_DIR}/projects" "${MAIN_DIR}/file-history" "${MAIN_DIR}/session-env"

for p in "${PROVIDERS[@]}"; do
    D="${HOME}/.claude-${p}"
    mkdir -p "$D"

    # 共享层:插件与技能 symlink 到主位
    ln -sfn "${MAIN_DIR}/plugins" "${D}/plugins"
    ln -sfn "${MAIN_DIR}/skills"  "${D}/skills"

    # 共享会话池(v2.4):projects/file-history/session-env symlink 到主位
    # 有存量数据的真实目录(非空)不自动动,提示走迁移脚本
    for d in projects file-history session-env; do
        if [[ -L "${D}/${d}" ]]; then
            continue
        elif [[ -d "${D}/${d}" ]]; then
            if [[ -z "$(ls -A "${D}/${d}")" ]]; then
                rmdir "${D}/${d}"
            else
                echo "[warn] ${D}/${d} 有存量数据,请跑 templates/share-session-pool.sh"
                continue
            fi
        fi
        ln -sfn "${MAIN_DIR}/${d}" "${D}/${d}"
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
