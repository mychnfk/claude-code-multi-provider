# Claude Code 多供应商切换 v2 (CLAUDE_CONFIG_DIR 物理隔离)
# 放在 shell 启动文件里(zsh 示例:~/.config/zsh/zshrc.d/99-claude-providers.zsh)
# 所有密钥走系统钥匙串,本文件可安全提交 dotfiles 仓库
#
# macOS 存 key(一次性):
#   security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "kimi-api-key"     -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "glm-api-key"      -w "sk-xxx"

# 默认路(自建中转)的 BASE_URL/key 在主 ~/.claude/settings.json 与 shell env,不走本文件。

# =============================================================================
# 供应商函数:CONFIG_DIR 指向 ~/.claude-<provider>,key 定向注入
# BASE_URL/模型档位/modelPicker 都在各 CONFIG_DIR 的 settings.json 里
# =============================================================================

# 注意 --settings 反压:在 ~ 目录下跑时,主 ~/.claude/settings.json 以「项目级」身份
# 进场(home 的 .claude 目录身兼用户级+项目级双职),其 availableModels 白名单会拦
# 供应商模型、env 压档位。让 CONFIG_DIR 里的同一 settings.json 再以 --settings 层
# (优先级高于项目层)进场一遍即可压回。因此函数必须带 --settings。

function claude-ds {
    if [[ -z "$DEEPSEEK_API_KEY" ]]; then
        echo "Error: DEEPSEEK_API_KEY is not set" >&2
        return 1
    fi
    CLAUDE_CONFIG_DIR="$HOME/.claude-deepseek" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" \
        claude --settings "$HOME/.claude-deepseek/settings.json" "$@"
}

function claude-kimi {
    if [[ -z "$KIMI_API_KEY" ]]; then
        echo "Error: KIMI_API_KEY is not set" >&2
        return 1
    fi
    CLAUDE_CONFIG_DIR="$HOME/.claude-kimi" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$KIMI_API_KEY" \
        claude --settings "$HOME/.claude-kimi/settings.json" "$@"
}

function claude-glm {
    if [[ -z "$GLM_API_KEY" ]]; then
        echo "Error: GLM_API_KEY is not set" >&2
        return 1
    fi
    CLAUDE_CONFIG_DIR="$HOME/.claude-glm" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY" \
        claude --settings "$HOME/.claude-glm/settings.json" "$@"
}
