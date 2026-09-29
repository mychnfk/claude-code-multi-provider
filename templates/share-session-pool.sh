#!/usr/bin/env bash
# claude-code-multi-provider v2.4:存量会话池迁移
# 把各 CONFIG_DIR 的 projects / file-history / session-env 合并进主位 ~/.claude/ 后替换为 symlink。
# 迁移后四入口(claude / claude-glm / claude-kimi / claude-ds)同一会话池,
# 任意会话可跨供应商 --resume(继续会话即切换模型),--continue 与 TUI /resume 列表同步打通。
#
# 安全设计:
# - 活跃会话的 jsonl 用硬链接而非 mv——同卷 mv 后 fd 虽然跟 inode 走,但"mv 后 symlink 前"
#   的窗口内若按旧路径重开(append 模式新建文件)会分叉会话;硬链接让新旧路径写同一 inode,窗口归零
# - 子目录(mv)与 file-history/session-env(session-id 目录,无法硬链接)窗口极小,可接受
# - 旧目录整体改名 *.pre-share-<日期> 备份,可回滚;确认跨供应商 resume 正常后删除
#
# 用法: bash share-session-pool.sh   (幂等,已 symlink 的目录自动跳过)
set -euo pipefail

MAIN_DIR="${HOME}/.claude"
STAMP="$(date +%Y%m%d)"
PROVIDERS=(glm kimi deepseek)

# 主位三个目录兜底创建(CC 平时也会自建,空目录无害)
mkdir -p "${MAIN_DIR}/projects" "${MAIN_DIR}/file-history" "${MAIN_DIR}/session-env"

# 把一层 session-id 子目录从 $1 挪进 $2
merge_flat() {
    local src="$1" dst="$2" name
    for entry in "$src"/*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ -e "${dst}/${name}" ]]; then
            echo "  [skip] 目标已存在: ${name}"
            continue
        fi
        mv "$entry" "${dst}/${name}"
    done
}

# 目录替换为 symlink,旧目录改名备份
swap_to_symlink() {
    local p="$1" target="$2"
    if [[ -L "$p" ]]; then
        echo "  [ok] 已是 symlink,跳过"
        return 0
    fi
    if [[ -d "$p" ]]; then
        mv "$p" "${p}.pre-share-${STAMP}"
    fi
    ln -s "$target" "$p"
}

for p in "${PROVIDERS[@]}"; do
    D="${HOME}/.claude-${p}"
    [[ -d "$D" ]] || { echo "[skip] ${D} 不存在"; continue; }

    # projects:<cwd>/<entry> 两层;普通文件硬链接,子目录 mv,memory symlink 跳过(主位已有真身)
    if [[ -d "${D}/projects" && ! -L "${D}/projects" ]]; then
        for cwd_dir in "${D}/projects"/*/; do
            [[ -d "$cwd_dir" ]] || continue
            cwd_name="$(basename "$cwd_dir")"
            dst="${MAIN_DIR}/projects/${cwd_name}"
            mkdir -p "$dst"
            for f in "$cwd_dir"*; do
                [[ -e "$f" ]] || continue
                name="$(basename "$f")"
                [[ "$name" == "memory" ]] && continue
                if [[ -e "${dst}/${name}" ]]; then
                    echo "  [skip] ${cwd_name}/${name}"
                    continue
                fi
                if [[ -d "$f" ]]; then
                    mv "$f" "${dst}/${name}"
                else
                    ln "$f" "${dst}/${name}"
                fi
            done
        done
        echo "[ok] ${D}/projects 已合并"
    fi

    # file-history / session-env:一层 session-id 子目录,整目录 mv
    for d in file-history session-env; do
        if [[ -d "${D}/${d}" && ! -L "${D}/${d}" ]]; then
            merge_flat "${D}/${d}" "${MAIN_DIR}/${d}"
            echo "[ok] ${D}/${d} 已合并"
        fi
    done

    # 三个目录替换为 symlink
    for d in projects file-history session-env; do
        echo "[swap] ${D}/${d}"
        swap_to_symlink "${D}/${d}" "${MAIN_DIR}/${d}"
    done
done

echo "done. 备份在各 CONFIG_DIR/*.pre-share-${STAMP},确认跨供应商 --resume 正常后可删。"
echo "验收(零成本): ANTHROPIC_BASE_URL=http://127.0.0.1:9 claude --resume <对方池的会话id> -p hi"
echo "  报 ECONNREFUSED = 会话查找已通过;报 No conversation found = 仍在池外。"
