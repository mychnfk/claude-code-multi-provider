# claude-code-multi-provider

> Claude Code 多供应商并行接入方案 v2:默认 `claude` 走自建中转,`claude-glm` / `claude-kimi` / `claude-ds` 秒切第三方直连——CONFIG_DIR 物理隔离,互不污染,`/model` 显示真实模型名。
>
> A production-tested setup for running Claude Code across multiple Anthropic-compatible providers (self-hosted relay, DeepSeek, Kimi, GLM...) with one-command switching, zero cross-contamination, and real model names in the /model picker.

## 效果

```bash
claude           # 默认:自建中转(sub2api),Claude 全家桶
claude-glm       # 智谱直连:/model 显示 GLM 5.3 / 5.2 / 5.3 Flash 真名
claude-ds  # DeepSeek 直连:pro 跑主循环,flash 跑小任务,1M 上下文
claude-kimi      # Kimi 直连:全档位 k3
```

## 设计:四层隔离(v2)

```
启动层   CLAUDE_CONFIG_DIR=<provider目录>  官方多账号原语,settings/projects/登录态全隔离
凭证层   ANTHROPIC_API_KEY= 显式清空       主路 key 绝不泄给第三方
         ANTHROPIC_AUTH_TOKEN 定向注入     Bearer vs x-api-key 行为可预测
         密钥全部进系统 Keychain           配置文件零明文,可进 dotfiles 仓库
模型层   全档位别名 + modelPicker 真名行   opus/sonnet/haiku 档位映射 + /model 真名
共享层   plugins/skills/memory symlink    三路共享插件、技能、跨供应商记忆
```

**v1→v2 根因**:v1 的 `claude --settings <file>` 方案在 Claude Code 2.1.278 失效——主 `~/.claude/settings.json` env 块压过 `--settings` 文件的档位别名与 modelPicker 解析(env 写入与 /model 解析是两条合并路径,与官方文档相悖)。`CLAUDE_CONFIG_DIR` 是官方文档明确背书的多账号并行原语,物理隔离后不存在合并问题。完整实证见 [SKILL.md](SKILL.md)。

## 快速开始

```bash
# 1. 密钥进 macOS Keychain(Linux 用 secret-tool / pass 等价替换)
security add-generic-password -a "$USER" -s "glm-api-key"      -w "sk-xxx"
security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx"
security add-generic-password -a "$USER" -s "kimi-api-key"     -w "sk-xxx"

# 2. 建三个 CONFIG_DIR + symlink 共享层 + 迁移 enabledPlugins(幂等)
bash templates/setup-config-dirs.sh

# 3. zsh 函数就位,重开 shell
cp templates/zsh-functions.zsh ~/.config/zsh/zshrc.d/99-claude-providers.zsh

# 4. 模板 settings-*.json 已带默认端点,按需改成你的
```

详细方法论、验证清单(transcript 法)、11 条实测坑见 [SKILL.md](SKILL.md)(可直接作为 Claude Code skill 安装到 `~/.claude/skills/`)。

## 扩展第四路

Keychain 存 key → 复制一份 settings 模板放 `~/.claude-<name>/settings.json` → symlink plugins/skills → 加一个 10 行 zsh 函数。架构零改动。

## License

MIT
