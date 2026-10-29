#!/bin/bash
# 启动本地 LiteLLM 代理：把 Anthropic 协议翻译成 OpenAI 兼容协议
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载 .env（不存在则跳过；缺少关键变量会在后面报错）
if [ -f "$DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$DIR/.env"
  set +a
fi

# 检查必填变量
if [ -z "${GATEWAY_BASE_URL:-}" ] || [ -z "${GATEWAY_API_KEY:-}" ]; then
  echo "错误：请先复制 .env.example 为 .env，并填写 GATEWAY_BASE_URL 和 GATEWAY_API_KEY" >&2
  exit 1
fi

# 优先使用项目内 .venv 的 litellm，否则用全局安装的
if [ -x "$DIR/.venv/bin/litellm" ]; then
  LITELLM_BIN="$DIR/.venv/bin/litellm"
else
  LITELLM_BIN="$(command -v litellm || true)"
  if [ -z "$LITELLM_BIN" ]; then
    echo "错误：未找到 litellm，请先执行：" >&2
    echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
    exit 1
  fi
fi

exec "$LITELLM_BIN" --config "$DIR/config.yaml" --host 127.0.0.1 --port 4000
