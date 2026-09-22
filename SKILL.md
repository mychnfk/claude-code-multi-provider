---
name: claude-code-multi-provider
description: Claude Code 多供应商并行接入架构 v2——CLAUDE_CONFIG_DIR 物理隔离,默认链路零负担,函数级一键切换。当用户要把 Claude Code 同时接入多个 Anthropic 兼容端点(自建中转、DeepSeek、Kimi、GLM 等)、设计供应商热切换、自定义 /model 选择器(modelPicker 真实模型名)、或排查多路配置互相污染/--settings 不生效时使用。
---

# Claude Code 多供应商并行架构 v2:CONFIG_DIR 物理隔离

默认 `claude` 走自建中转,`claude-glm` / `claude-kimi` / `claude-deepseek` 函数秒切第三方直连,互不污染,`/model` 选择器显示各供应商真实模型名。

```bash
claude           # 默认:自建中转(sub2api),Claude 全家桶
claude-glm       # 智谱直连:/model 显示 GLM 5.3 / 5.2 / 5.3 Flash
claude-kimi      # Kimi 直连:全档位 k3
claude-deepseek  # DeepSeek 直连:pro 跑主循环,flash 跑小任务
```

## 为什么放弃 v1 的 `--settings` 方案

v1(2026-09 前使用):每供应商一个 settings 文件,函数里 `claude --settings ~/.claude/settings-xxx.json`。**在 Claude Code 2.1.278 上失效**,根因实证(transcript + `--debug-file` 逆向):

1. **env 双路径合并不一致**:进程环境变量写入是 `--settings` 后应用(同名键它赢),但 **`/model` 档位解析与 modelPicker 解析走另一条路径,以主 `~/.claude/settings.json` 为准**。主文件 env 里的 `ANTHROPIC_DEFAULT_*` 会压掉 `--settings` 文件的同名键——官方文档声称的优先级(`--settings` > user)与实现不符。
2. **modelPicker 在 `--settings` 层的实际渲染不可靠**(同一解析路径)。
3. 唯一幸存的是主文件没定义的键(如 `ANTHROPIC_MODEL`)——这就是"只有 default 模型生效"的机制。

任何 `--settings` 缝补都是在押注未文档化的合并行为。**`CLAUDE_CONFIG_DIR` 是官方 env-vars 文档明确背书的多账号并行原语**("Useful for running multiple accounts side by side"),物理隔离后不存在合并问题。

## v2 架构:四层隔离

```
启动层   CLAUDE_CONFIG_DIR=<provider目录>     官方多账号原语,settings/projects/登录态全隔离
凭证层   ANTHROPIC_API_KEY= 显式清空          主路 key 绝不泄给第三方
         ANTHROPIC_AUTH_TOKEN 定向注入        Keychain 取 key,配置零明文
模型层   全档位别名 + modelPicker 真名行      opus/sonnet/haiku 档位映射 + /model 显示真实模型名
共享层   plugins/skills/memory symlink        三路共享插件、技能、跨供应商记忆
```

### 目录结构

```
~/.claude                    # 主位:默认路(中转),一个字节不用动
~/.claude-glm/               # 每供应商一个完整 CONFIG_DIR
├── settings.json            # BASE_URL + 全档位 env + modelPicker + enabledPlugins + statusLine/hooks
├── plugins  -> ~/.claude/plugins    # symlink 共享(8 个官方插件)
├── skills   -> ~/.claude/skills     # symlink 共享
└── projects/<cwd>/memory -> 主位同路径  # 记忆共享(按工作目录)
~/.claude-kimi/  ~/.claude-deepseek/ # 同构
```

### zsh 函数(v2)

```zsh
function claude-glm {
    if [[ -z "$GLM_API_KEY" ]]; then
        echo "Error: GLM_API_KEY is not set" >&2; return 1
    fi
    CLAUDE_CONFIG_DIR="$HOME/.claude-glm" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY" \
        claude --settings "$HOME/.claude-glm/settings.json" "$@"
}
```

`--settings` 指回同一文件不是冗余——见坑 9/10:在 home 目录跑时,主 settings.json 以项目级身份进场,必须用 `--settings` 层(优先级高于项目层)把同一份配置再压一遍。

BASE_URL 写在各目录 settings.json 的 env 块(会覆盖 shell 里 export 的值),key 由函数从 Keychain 注入——目录自成一体可进 dotfiles,凭证不落盘。

## 关键坑(全部实测,2.1.278)

1. **`enabledPlugins` 必须复制到每个 CONFIG_DIR 的 settings.json**——插件启用状态是 settings.json 顶层键,不跟随 plugins/ 目录 symlink。漏了它:8 个插件只认 1 个 builtin,技能数从 24 掉到 15。`installed_plugins.json` 只是它的同步产物。
2. **modelPicker 行级字段真身是 `{ model, label?, description?, behavesAs? }`**——官方文档(settings-reference)滞后未收录 `behavesAs`,但二进制 schema 实证存在。注意 `labelOverride`/`supports1m`/`prefer1m` 等字段名**不存在**,写了整行被静默丢弃。`behavesAs: "claude-opus-5"` = 借用已知模型的客户端 profile(prompt/能力/effort 默认),是第三方模型进 picker 的关键。
3. **`ANTHROPIC_SMALL_FAST_MODEL` 已废弃**,统一用 `ANTHROPIC_DEFAULT_HAIKU_MODEL`。
4. **兼容端点的静默兜底假象**:bigmodel 对不认识的模型名(如误发的 `claude-opus-5`)照样返回正常回复——"能出活"≠"用对模型"。验证只能看 transcript(`~/.claude-<p>/projects/<dir>/*.jsonl` 的 `message.model`)。
5. **gateway discovery 对第三方直连无效**:`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` 拉网关 `/v1/models` 后有硬编码 filter `/(claude|anthropic)/i`,非 claude 系模型全滤掉(debug 日志 `0 usable models after filter`)。它只适用于模型名带 claude 的中转。
6. **新 CONFIG_DIR 并发初始化会 exit=1**:多个进程同时首跑同一新目录会撞 `.claude.json` 初始化,单跑即恢复,日常无影响。
7. **`--debug-file <path>` 是 `-p` 模式下唯一日志出口**(`--debug` 不写 stderr);TUI 在 expect/script 的 pty 下不渲染,抓屏验证 `/model` 界面不可行,只能人眼。
8. **memory symlink 按工作目录建**:`~/.claude-<p>/projects/<cwd>/memory -> ~/.claude/projects/<cwd>/memory`,新工作目录首次会话后补一条。
9. **home 目录的 .claude 双职陷阱(必踩)**:`~/.claude/settings.json` 既是用户级配置,又是"home 作为项目目录"的**项目级** `.claude/settings.json`。CONFIG_DIR 只隔离用户层;在 home 下跑供应商会话,主文件以项目级身份再次进场——优先级 local project > shared project > user,项目层的 `availableModels` 白名单和 env 会压过 CONFIG_DIR 里的同名配置。症状:启动警告 `Model "glm-5.3[1m]" is restricted by your organization's settings. Using claude-opus-5[1m] instead`、/model 列表显示的是主文件的行。**对策**:函数里 `--settings "$CONFIG_DIR/settings.json"` 让同一文件以更高优先级层(仅次于 managed)再进场压回。注意在干净目录(如 /tmp)测试时该陷阱不出现——**验证必须在 home 复现真实场景**。
10. **availableModels 拦的是档位映射目标**:主文件白名单不含 `glm-5.2` 时,`--model sonnet` 的档位值 glm-5.2 被白名单拦下后**回落到主文件的档位值**(claude-sonnet-5)——看起来像"档位被压",其实是"映射目标未放行"。对策:各 CONFIG_DIR 的 settings.json **必须自带 availableModels**(供应商模型全名 + opus/sonnet/haiku 档位名),`--settings` 层的白名单会整体压过项目层。
11. **每 CONFIG_DIR 首次交互会话会弹一次 trust 对话框**(信任状态按 CONFIG_DIR 分存),接受一次即永久;`-p` 模式不弹但项目层 env/白名单照常应用。

## 快速开始

```bash
git clone https://github.com/<you>/claude-code-multi-provider
# 1. 存 key(一次性)
security add-generic-password -a "$USER" -s "glm-api-key" -w "sk-xxx"
# 2. 建三个 CONFIG_DIR + symlink + 迁移 enabledPlugins/statusLine/hooks
bash templates/setup-config-dirs.sh
# 3. zsh 函数放 shell 启动文件
cp templates/zsh-functions.zsh ~/.config/zsh/zshrc.d/99-claude-providers.zsh
# 4. 验证(必须看 transcript,别信响应)
CLAUDE_CONFIG_DIR="$HOME/.claude-glm" ANTHROPIC_API_KEY= \
  ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY" claude --model sonnet -p "say ok"
ls -t ~/.claude-glm/projects/<cwd>/*.jsonl | head -1  # message.model 应为 glm-5.2
```

## 验证清单(每次新供应商/升级 Claude Code 后)

- [ ] 默认模型:`-p` 一发,transcript 的 model = 期望值
- [ ] 三档位:`--model opus/sonnet/haiku` 各一发,transcript 逐一核对(防兜底假象)
- [ ] 技能数对照:主位与 provider 位 `--debug-file` 里 `Sending N skills` 相等
- [ ] 人眼看一次 `/model`:真实模型名行 + `replaceBuiltInOptions` 生效
