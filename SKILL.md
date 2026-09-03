---
name: claude-code-multi-provider
description: Claude Code 多供应商并行接入架构——默认链路零负担,函数级一键切换,凭证/配置/模型三层隔离。当用户要把 Claude Code 同时接入多个 Anthropic 兼容端点(自建中转、DeepSeek、Kimi、GLM 等)、设计供应商热切换、或排查多路配置互相污染时使用。
---

# Claude Code 多供应商三路并行架构

一套经过生产验证的 Claude Code 多供应商接入方案:**默认 `claude` 走自建中转,`claude-deepseek` / `claude-kimi` 两个函数秒切备用供应商**,三路并存、互不污染。

## 设计目标

1. **默认路径零负担**:日常 `claude` 命令行为完全不变
2. **切换零心智**:想换供应商,换个命令名而已,不需要改任何文件、不需要记环境变量
3. **污染零容忍**:任何一路的 key、base_url、模型配置,绝不可能漏到另一路

## 核心架构:三层隔离

### 第一层:启动层隔离 —— zsh 函数 + `--settings` 分文件

每个供应商一个 shell 函数,通过 `--settings` 指向**独立的 settings 文件**:

```zsh
claude          # 默认:主 settings.json + 全局 env(自建中转)
claude-deepseek # --settings ~/.claude/settings-deepseek.json
claude-kimi     # --settings ~/.claude/settings-kimi.json
```

**为什么不能把供应商配置写进主 settings.json**:Claude Code 运行中会**实时回写**主 settings.json(改主题、权限等都会触发)。供应商配置放进去,既容易被回写覆盖,又会污染默认路。独立文件则完全由你掌控。

### 第二层:凭证隔离 —— 显式清空 + 定向注入

```zsh
ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" claude --settings ...
```

两个动作缺一不可:

- `ANTHROPIC_API_KEY=`(**显式置空**):主配置里全局 export 了中转 key。不清空,它会被一起带到 DeepSeek/Kimi——你的中转 key 就泄给了第三方。
- `ANTHROPIC_AUTH_TOKEN`(定向注入):多数第三方 Anthropic 兼容端点认 Bearer token(AUTH_TOKEN)而非 x-api-key(API_KEY)。两者都设时行为因版本而异,显式清空 + 单一注入是唯一可预测的姿作。

**密钥存储进系统钥匙串,配置零明文**:

```zsh
# macOS Keychain(先手工存入一次:security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx")
export DEEPSEEK_API_KEY=$(security find-generic-password -a "$USER" -s "deepseek-api-key" -w 2>/dev/null)
```

Linux 可用 `secret-tool` / `pass` 等价替换。这样 zsh 配置文件本身可以安全进 dotfiles 仓库。

### 第三层:模型映射隔离 —— 全档位别名接管

Claude Code 内部**按档位调度模型**:主循环用 opus/sonnet 档,轻量任务(标题生成、压缩、子代理)会调 haiku 档和 SMALL_FAST。只设 `ANTHROPIC_MODEL` 是不够的——小任务会尝试调官方 haiku,在非官方端点上直接 404 或走错模型。

正确姿势是把**所有档位别名都接管**:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding",
    "ANTHROPIC_MODEL": "k3",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "k3",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "k3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "k3",
    "ANTHROPIC_SMALL_FAST_MODEL": "k3",
    "CLAUDE_CODE_SUBAGENT_MODEL": "k3"
  }
}
```

想区分档位也可以(如 DeepSeek 路:pro 跑主循环、flash 跑小任务),按档位分别映射即可。

### 模型选择器的三个机制(容易搞混)

- `availableModels` 是**白名单不是注册表**:只能把选择器筛剩列出的几个,不会新增模型
- `/model` 默认读客户端内置注册表,走中转时不自动发现远端模型
- `ANTHROPIC_CUSTOM_MODEL_OPTION` + `..._NAME`:把一个自定义模型 ID 加进选择器(若配了白名单,ID 必须也在白名单里)

### 体验调优(非必须但推荐)

| 配置 | 作用 |
|---|---|
| `API_TIMEOUT_MS: "600000"` | 第三方端点长任务防超时 |
| `DISABLE_COST_WARNINGS: "1"` | 非官方计价,成本告警是纯噪音 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` | 非官方端点关掉遥测等杂流量 |

## 安装

```bash
# 1. 拷模板
cp templates/zsh-functions.zsh ~/.config/zsh/zshrc.d/99-claude-providers.zsh  # 按你的 shell 加载方式调整
cp templates/settings-deepseek.json ~/.claude/settings-deepseek.json
cp templates/settings-kimi.json ~/.claude/settings-kimi.json

# 2. 密钥进 Keychain
security add-generic-password -a "$USER" -s "deepseek-api-key" -w "你的key"
security add-generic-password -a "$USER" -s "kimi-api-key" -w "你的key"

# 3. 按模板注释改成你的端点和模型名,重开终端
```

## 验证(重要)

**菜单里有 ≠ 后端能用**。改完验证三层:

1. 配置文件语法:`python3 -m json.tool ~/.claude/settings-deepseek.json`
2. 端点列模型:`curl $BASE_URL/v1/models -H "x-api-key: $KEY"`
3. **真实请求**:启动对应命令发一条消息。中转/网关可能有客户端门禁(如"只认 Claude Code 客户端"),裸 curl 被拦不代表 CLI 不通,反之亦然——以真实 CLI 请求为准

## 坑(生产实录)

- **改完必须完全退出 claude 再重开**:env 只在启动时读一次
- **主 settings.json 会被运行中的 app 回写**:手工编辑前先退出所有会话,否则可能被覆盖回去
- **`[1m]` 后缀**(如 `deepseek-v4-pro[1m]`)= 请求 1M 上下文 beta header,发给 provider 前会被剥离;带不带后缀只是上下文长度差别
- **模型优先级**:`/model 命令` > `--model` 参数 > `ANTHROPIC_MODEL` > settings `model` 字段

## 扩展第四路

新供应商只需三步:Keychain 存 key → 复制一份 settings 模板改 BASE_URL 和模型名 → 加一个 12 行的 zsh 函数。架构不需要任何改动——这正是三层隔离的收益。
