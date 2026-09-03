# claude-code-multi-provider

> Claude Code 多供应商并行接入方案:默认 `claude` 走自建中转,`claude-deepseek` / `claude-kimi` 秒切备用供应商——三路并存,互不污染。
>
> A production-tested setup for running Claude Code across multiple Anthropic-compatible providers (self-hosted relay, DeepSeek, Kimi, GLM...) with one-command switching and zero cross-contamination.

## 效果

```bash
claude           # 默认:自建中转(sub2api),Claude 全家桶 + 自定义模型进 /model 菜单
claude-deepseek  # 秒切 DeepSeek:pro 跑主循环,flash 跑小任务,1M 上下文
claude-kimi      # 秒切 Kimi K3:全档位 k3
```

## 设计:三层隔离

```
启动层   zsh 函数 + --settings 分文件     每路独立配置,主 settings.json 零污染
凭证层   ANTHROPIC_API_KEY= 显式清空      主路 key 绝不泄给第三方
         ANTHROPIC_AUTH_TOKEN 定向注入    Bearer vs x-api-key 行为可预测
         密钥全部进系统 Keychain          配置文件零明文,可进 dotfiles 仓库
模型层   全档位别名接管                   OPUS/SONNET/HAIKU/SMALL_FAST/SUBAGENT
                                         CC 内部按档位调度,只设 MODEL 会踩空
```

**为什么主 settings.json 碰不得**:Claude Code 运行中会实时回写它(改主题、权限都触发)。供应商配置放进去,既可能被覆盖,又污染默认路。独立 `--settings` 文件完全由你掌控。

## 快速开始

```bash
# 1. 拷模板
cp templates/zsh-functions.zsh ~/.config/zsh/zshrc.d/99-claude-providers.zsh
cp templates/settings-deepseek.json ~/.claude/settings-deepseek.json
cp templates/settings-kimi.json ~/.claude/settings-kimi.json

# 2. 密钥进 macOS Keychain(Linux 用 secret-tool / pass 等价替换)
security add-generic-password -a "$USER" -s "relay-api-key"    -w "sk-xxx"
security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx"
security add-generic-password -a "$USER" -s "kimi-api-key"     -w "sk-xxx"

# 3. 模板里换成你的端点和模型名,完全退出 claude 重开
```

详细方法论、验证清单、生产踩坑实录见 [SKILL.md](SKILL.md)(可直接作为 Claude Code skill 安装到 `~/.claude/skills/`)。

## 扩展第四路

Keychain 存 key → 复制 settings 模板改两行 → 加一个 12 行 zsh 函数。架构零改动。

## License

MIT
