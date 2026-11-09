# Claude Code 多供应商切换 v2 (CLAUDE_CONFIG_DIR 物理隔离)
# 放在 shell 启动文件里(zsh 示例:~/.config/zsh/zshrc.d/99-claude-providers.zsh)
# 所有密钥走系统钥匙串,本文件可安全提交 dotfiles 仓库
#
# macOS 存 key(一次性):
#   security add-generic-password -a "$USER" -s "deepseek-api-key" -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "kimi-api-key"     -w "sk-xxx"
#   security add-generic-password -a "$USER" -s "glm-api-key"      -w "sk-xxx"

# 默认路(自建中转)的 BASE_URL/key 在主 ~/.claude/settings.json 与 shell env,不走本文件。
# 交互 shell 启动时默认回主池:清除父进程可能带入的第三方运行态,避免在 provider
# 会话的嵌套 shell 里敲裸 claude 时沿用对方的 CONFIG_DIR/模型/key(坑 20)。
# AUTH_TOKEN 必须 unset 而非 export 空串:空 Bearer 仍会压过 API_KEY。
unset CLAUDE_CONFIG_DIR ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL \
      ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL_NAME \
      ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL_NAME \
      ANTHROPIC_DEFAULT_HAIKU_MODEL \
      ANTHROPIC_CUSTOM_MODEL_OPTION ANTHROPIC_CUSTOM_MODEL_OPTION_NAME \
      CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_EFFORT_LEVEL \
      CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_CODE_MODEL_CAPABILITIES \
      ENABLE_TOOL_SEARCH

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
    echo "→ [deepseek] api.deepseek.com 直连" >&2
    CLAUDE_CONFIG_DIR="$HOME/.claude-deepseek" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" \
        claude --settings "$HOME/.claude-deepseek/settings.json" "$@"
}

function claude-kimi {
    if [[ -z "$KIMI_API_KEY" ]]; then
        echo "Error: KIMI_API_KEY is not set" >&2
        return 1
    fi
    echo "→ [kimi] api.kimi.com 直连" >&2
    CLAUDE_CONFIG_DIR="$HOME/.claude-kimi" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$KIMI_API_KEY" \
        claude --settings "$HOME/.claude-kimi/settings.json" "$@"
}

function claude-glm {
    if [[ -z "$GLM_API_KEY" ]]; then
        echo "Error: GLM_API_KEY is not set" >&2
        return 1
    fi
    echo "→ [glm] open.bigmodel.cn 直连" >&2
    CLAUDE_CONFIG_DIR="$HOME/.claude-glm" \
        ANTHROPIC_API_KEY= ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY" \
        claude --settings "$HOME/.claude-glm/settings.json" "$@"
}

# =============================================================================
# ccp-doctor <pool> — 1-token 健康检查 + TTFT(首字节即停)
# pool: main|glm|kimi|deepseek。从落盘 settings.json 读 BASE_URL + 默认模型
# (剥 [1m]——bigmodel/kimi 直连必须裸名),key 走 Keychain,GLM 探活 timeout 给 90s。
# 主池 BASE_URL 硬编码(不继承 shell env,避免跨池终端里跑 doctor 拿错 URL)。
# 主池分组若要求 CC 客户端 UA,curl 带 user-agent 头。
# =============================================================================
# 主池(自建中转)地址,按你的中转改:
STARIVER_BASE_URL="${STARIVER_BASE_URL:-https://stariver.top}"

ccp-doctor() {
  local pool="${1:-}"
  if [[ -z "$pool" ]]; then
    echo "usage: ccp-doctor <main|glm|kimi|deepseek>" >&2
    return 1
  fi

  local cfg svc timeout
  case "$pool" in
    main|stariver) cfg="$HOME/.claude/settings.json"; svc="stariver-api-key"; timeout=60 ;;
    glm)           cfg="$HOME/.claude-glm/settings.json"; svc="glm-api-key"; timeout=90 ;;
    kimi)          cfg="$HOME/.claude-kimi/settings.json"; svc="kimi-api-key"; timeout=90 ;;
    deepseek|ds)   cfg="$HOME/.claude-deepseek/settings.json"; svc="deepseek-api-key"; timeout=60 ;;
    *) echo "ccp-doctor: 未知池 '$pool'(可选 main|glm|kimi|deepseek)" >&2; return 1 ;;
  esac

  [[ -f "$cfg" ]] || { echo "ccp-doctor: $cfg 不存在" >&2; return 1; }

  local base model key
  if [[ "$pool" == "main" || "$pool" == "stariver" ]]; then
    base="$STARIVER_BASE_URL"
  else
    base=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$cfg")
  fi
  model=$(jq -r '.env.ANTHROPIC_MODEL // empty' "$cfg")
  model="${model%%\[1m\]}"   # 剥 [1m] 后缀——bigmodel/kimi 直连必须裸名
  [[ -z "$model" ]] && model="claude-sonnet-5-5"  # 主池无 ANTHROPIC_MODEL 时给个已知模型

  key=$(security find-generic-password -a "$USER" -s "$svc" -w 2>/dev/null) || {
    echo "ccp-doctor: Keychain 无 $svc" >&2; return 1
  }

  echo "→ [$pool] $base"
  echo "  model=$model key=${#key}chars timeout=${timeout}s"

  local url="$base/v1/messages"
  local body='{"model":"'"$model"'","max_tokens":1,"stream":true,"messages":[{"role":"user","content":"hi"}]}'
  local tmp http_code t_start t_end ttft
  tmp=$(mktemp /tmp/ccp-doctor-XXXXXXXX)
  t_start=$(python3 -c 'import time; print(time.time())')

  http_code=$(curl -sS -N --max-time "$timeout" -o "$tmp" -w '%{http_code}' \
    -X POST "$url" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "authorization: Bearer $key" \
    -H "x-api-key: $key" \
    -H "user-agent: claude-cli/2.1.303 (external, cli)" \
    -d "$body" 2>"$tmp.err") || {
      local rc=$?
      echo "✗ [$pool] 连接失败(curl rc=$rc): $(head -1 "$tmp.err" 2>/dev/null)" >&2
      echo "  可能: 网关未起/DNS/代理拦截/超时(${timeout}s)" >&2
      rm -f "$tmp" "$tmp.err"; return 1
    }
  t_end=$(python3 -c 'import time; print(time.time())')
  ttft=$(python3 -c "print(f'{$t_end - $t_start:.2f}')")

  case "$http_code" in
    200)
      echo "✓ [$pool] 200 OK  TTFT=${ttft}s"
      local got_model
      got_model=$(grep -o '"model":"[^"]*"' "$tmp" | head -1 | cut -d'"' -f4)
      [[ -n "$got_model" ]] && echo "  上游实际服务模型: $got_model"
      ;;
    400) echo "✗ [$pool] 400 — 模型名错/参数不被接受" >&2; echo "  响应: $(head -c 300 "$tmp")" >&2 ;;
    401|403) echo "✗ [$pool] $http_code 认证失败 — key 被拒/过期/无权访问该模型" >&2; echo "  响应: $(head -c 300 "$tmp")" >&2 ;;
    404) echo "✗ [$pool] 404 — 端点路径错(检查 BASE_URL 前缀)" >&2; echo "  URL: $url" >&2 ;;
    429) echo "✗ [$pool] 429 — 配额尽/限流" >&2; echo "  响应: $(head -c 300 "$tmp")" >&2 ;;
    5*) echo "✗ [$pool] $http_code — 上游服务错误/网关故障" >&2; echo "  响应: $(head -c 300 "$tmp")" >&2 ;;
    *) echo "? [$pool] HTTP $http_code  TTFT=${ttft}s" >&2; echo "  响应: $(head -c 300 "$tmp")" >&2 ;;
  esac
  rm -f "$tmp" "$tmp.err"
}
