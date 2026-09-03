# Claude Code 多供应商配置模板
# 放在 shell 启动文件里(zsh 示例:~/.config/zsh/zshrc.d/99-claude-providers.zsh)
# 所有密钥走系统钥匙串,本文件可安全提交 dotfiles 仓库
#
# macOS 存 key(一次性):
#   security add-generic-password -a "$USER" -s "relay-api-key"    -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "kimi-api-key"     -w "sk-xxx"

# =============================================================================
# 默认路:自建中转(Anthropic API 兼容)
# =============================================================================
# 示例为自建的 sub2api 中转;换成任何 Anthropic 兼容端点均可
export ANTHROPIC_BASE_URL="https://stariver.top"   # ← 换成你的中转地址
export ANTHROPIC_API_KEY=$(security find-generic-password -a "$USER" -s "relay-api-key" -w 2>/dev/null)

# 默认路的模型选择器扩展在 ~/.claude/settings.json 的 env 段:
#   ANTHROPIC_CUSTOM_MODEL_OPTION=claude-fable-5-1  (把中转模型加进 /model 菜单)
#   availableModels 白名单里必须同时包含该 ID,否则菜单里看不到

# =============================================================================
# 备用路 A:DeepSeek(官方 Anthropic 兼容端点)
# =============================================================================
export DEEPSEEK_API_KEY=$(security find-generic-password -a "$USER" -s "deepseek-api-key" -w 2>/dev/null)

function claude-deepseek {
    if [[ -z "$DEEPSEEK_API_KEY" ]]; then
        echo "Error: DEEPSEEK_API_KEY is not set" >&2
        return 1
    fi
    # 显式清空主路 key + 定向注入本路 token + 独立 settings 文件
    ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" \
        claude --settings "$HOME/.claude/settings-deepseek.json" "$@"
}

# =============================================================================
# 备用路 B:Kimi(Moonshot Anthropic 兼容端点)
# =============================================================================
export KIMI_API_KEY=$(security find-generic-password -a "$USER" -s "kimi-api-key" -w 2>/dev/null)

function claude-kimi {
    if [[ -z "$KIMI_API_KEY" ]]; then
        echo "Error: KIMI_API_KEY is not set" >&2
        return 1
    fi
    ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$KIMI_API_KEY" \
        claude --settings "$HOME/.claude/settings-kimi.json" "$@"
}

# =============================================================================
# 扩展第四路:复制上面任一函数,换 key 名和 settings 文件名即可
# =============================================================================
