#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
INVOKED_AS="$(basename "$0")"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

load_env

RUST_DIR="${RUST_DIR:-$ROOT_DIR/rust}"
CLAW_BIN="${CLAW_BIN:-$RUST_DIR/target/release/claw}"
CONDA_ENV_PREFIX="${CONDA_ENV_PREFIX:-}"
DEFAULT_CONDA_ENV_PREFIX="${DEFAULT_CONDA_ENV_PREFIX:-/home/yang/miniconda3/envs/claw-local}"
LOCAL_SERVER_USE_ACTIVE_CONDA="${LOCAL_SERVER_USE_ACTIVE_CONDA:-true}"
CLAW_PROVIDER="${CLAW_PROVIDER:-poe}"
CLAW_MODEL="${CLAW_MODEL:-claude-sonnet-4-6}"
CLAW_PERMISSION_MODE="${CLAW_PERMISSION_MODE:-workspace-write}"
CLAW_TRUST_BASH_IN_WORKSPACE_WRITE="${CLAW_TRUST_BASH_IN_WORKSPACE_WRITE:-false}"
CLAW_DEFAULT_PROMPT="${CLAW_DEFAULT_PROMPT:-summarize this workspace}"
LOCAL_MODEL_REF="${LOCAL_MODEL_REF:-/home/yang/Downloads/pretrained/Qwen3-4B}"
LOCAL_MODEL_ALIAS="${LOCAL_MODEL_ALIAS:-claw-local-model}"
LOCAL_MODEL_ROOT="${LOCAL_MODEL_ROOT:-$(dirname "$LOCAL_MODEL_REF")}"
LOCAL_ALLOWED_TOOLS="${LOCAL_ALLOWED_TOOLS:-read,glob,grep,edit,write,TodoWrite}"
LOCAL_SERVER_HOST="${LOCAL_SERVER_HOST:-127.0.0.1}"
LOCAL_SERVER_PORT="${LOCAL_SERVER_PORT:-8011}"
LOCAL_SERVER_DEVICE="${LOCAL_SERVER_DEVICE:-auto}"
LOCAL_SERVER_DTYPE="${LOCAL_SERVER_DTYPE:-auto}"
LOCAL_SERVER_ENABLE_CORS="${LOCAL_SERVER_ENABLE_CORS:-true}"
LOCAL_SERVER_CONTINUOUS_BATCHING="${LOCAL_SERVER_CONTINUOUS_BATCHING:-false}"
LOCAL_SERVER_PORT_SEARCH_LIMIT="${LOCAL_SERVER_PORT_SEARCH_LIMIT:-20}"
LOCAL_SERVER_STATE_FILE="${LOCAL_SERVER_STATE_FILE:-$ROOT_DIR/.claw/local-server.env}"

LOCAL_LAUNCHER_ARGS=()
LOCAL_MODEL_REQUEST=""
LOCAL_MODEL_WAS_EXPLICIT=0

usage() {
  cat <<'EOF'
Usage:
  ./start.sh help
  ./start.sh doctor
  ./start.sh build
  ./start.sh poe-cli
  ./start.sh poe-cli --model claude-sonnet-4-6
  ./start.sh poe-prompt "your prompt"
  ./start.sh local-server
  ./start.sh local-cli
  ./start.sh local-cli --local-model /path/to/model
  ./start.sh local-cli --list-local-models
  ./start.sh local-cli --permission-mode read-only
  ./start.sh local-prompt "your prompt"

Notes:
  - Configuration is loaded from .env by default.
  - Use ENV_FILE=/path/to/file ./start.sh ... to override.
  - `poe-*` uses POE_API_KEY / POE_BASE_URL.
  - `local-*` uses OPENAI_API_KEY / OPENAI_BASE_URL.
  - `--local-model` accepts either a local model path or an already served model id.
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

ensure_cargo_env() {
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
  fi
}

build_claw() {
  ensure_cargo_env
  require_cmd cargo
  (cd "$RUST_DIR" && cargo build --release -p claw-cli)
}

resolve_conda_env_prefix() {
  if [[ -n "$CONDA_ENV_PREFIX" ]]; then
    printf '%s\n' "$CONDA_ENV_PREFIX"
    return 0
  fi

  if [[ "$LOCAL_SERVER_USE_ACTIVE_CONDA" == "true" ]] \
    && [[ -n "${CONDA_PREFIX:-}" ]] \
    && [[ "${CONDA_DEFAULT_ENV:-}" != "base" ]]; then
    printf '%s\n' "$CONDA_PREFIX"
    return 0
  fi

  printf '%s\n' "$DEFAULT_CONDA_ENV_PREFIX"
}

doctor() {
  local resolved_conda_prefix=""
  resolved_conda_prefix="$(resolve_conda_env_prefix)"
  echo "ROOT_DIR=$ROOT_DIR"
  echo "ENV_FILE=$ENV_FILE"
  echo "RUST_DIR=$RUST_DIR"
  echo "CLAW_BIN=$CLAW_BIN"
  echo "CONDA_ENV_PREFIX=$CONDA_ENV_PREFIX"
  echo "DEFAULT_CONDA_ENV_PREFIX=$DEFAULT_CONDA_ENV_PREFIX"
  echo "LOCAL_SERVER_USE_ACTIVE_CONDA=$LOCAL_SERVER_USE_ACTIVE_CONDA"
  echo "RESOLVED_CONDA_ENV_PREFIX=$resolved_conda_prefix"
  echo "CLAW_PROVIDER=$CLAW_PROVIDER"
  echo "CLAW_MODEL=$CLAW_MODEL"
  echo "CLAW_PERMISSION_MODE=$CLAW_PERMISSION_MODE"
  echo "CLAW_TRUST_BASH_IN_WORKSPACE_WRITE=$CLAW_TRUST_BASH_IN_WORKSPACE_WRITE"
  echo "LOCAL_MODEL_REF=$LOCAL_MODEL_REF"
  echo "LOCAL_MODEL_ROOT=$LOCAL_MODEL_ROOT"
  echo "LOCAL_MODEL_ALIAS=$LOCAL_MODEL_ALIAS"
  echo "LOCAL_ALLOWED_TOOLS=$LOCAL_ALLOWED_TOOLS"
  echo "LOCAL_SERVER_STATE_FILE=$LOCAL_SERVER_STATE_FILE"
  if command -v conda >/dev/null 2>&1; then
    echo "conda=$(command -v conda)"
  fi
  if [[ -f "$HOME/.cargo/env" ]]; then
    echo "cargo_env=$HOME/.cargo/env"
  fi
}

has_claw_arg() {
  local needle="$1"
  shift || true
  for arg in "$@"; do
    if [[ "$arg" == "$needle" || "$arg" == "$needle="* ]]; then
      return 0
    fi
  done
  return 1
}

parse_local_launcher_args() {
  LOCAL_LAUNCHER_ARGS=()
  LOCAL_MODEL_REQUEST=""
  LOCAL_MODEL_WAS_EXPLICIT=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local-model)
        if [[ $# -lt 2 ]]; then
          echo "missing value for --local-model" >&2
          exit 1
        fi
        LOCAL_MODEL_REQUEST="$2"
        LOCAL_MODEL_WAS_EXPLICIT=1
        shift 2
        ;;
      --local-model=*)
        LOCAL_MODEL_REQUEST="${1#*=}"
        LOCAL_MODEL_WAS_EXPLICIT=1
        shift
        ;;
      --list-local-models)
        list_local_models
        exit 0
        ;;
      --model)
        if [[ $# -lt 2 ]]; then
          echo "missing value for --model" >&2
          exit 1
        fi
        LOCAL_MODEL_REQUEST="$2"
        LOCAL_MODEL_WAS_EXPLICIT=1
        shift 2
        ;;
      --model=*)
        LOCAL_MODEL_REQUEST="${1#*=}"
        LOCAL_MODEL_WAS_EXPLICIT=1
        shift
        ;;
      *)
        LOCAL_LAUNCHER_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

list_local_models() {
  if [[ ! -d "$LOCAL_MODEL_ROOT" ]]; then
    echo "LOCAL_MODEL_ROOT does not exist: $LOCAL_MODEL_ROOT" >&2
    exit 1
  fi

  find "$LOCAL_MODEL_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort
}

build_claw_command() {
  local default_model="$1"
  shift || true

  local -a cmd=("$CLAW_BIN")
  if ! has_claw_arg "--model" "$@"; then
    cmd+=(--model "$default_model")
  fi

  if ! has_claw_arg "--permission-mode" "$@" && ! has_claw_arg "--dangerously-skip-permissions" "$@"; then
    cmd+=(--permission-mode "$CLAW_PERMISSION_MODE")
  fi

  cmd+=("$@")
  printf '%s\n' "${cmd[@]}"
}

run_poe_cli() {
  if [[ -z "${POE_API_KEY:-}" ]]; then
    echo "POE_API_KEY is required for poe-cli" >&2
    exit 1
  fi
  ensure_cargo_env
  unset OPENAI_API_KEY OPENAI_BASE_URL XAI_API_KEY XAI_BASE_URL
  export POE_BASE_URL="${POE_BASE_URL:-https://api.poe.com}"
  export POE_API_KEY
  mapfile -t cmd < <(build_claw_command "$CLAW_MODEL" "$@")
  exec "${cmd[@]}"
}

run_poe_prompt() {
  if [[ -z "${POE_API_KEY:-}" ]]; then
    echo "POE_API_KEY is required for poe-prompt" >&2
    exit 1
  fi
  local prompt="${1:-$CLAW_DEFAULT_PROMPT}"
  shift || true
  ensure_cargo_env
  unset OPENAI_API_KEY OPENAI_BASE_URL XAI_API_KEY XAI_BASE_URL
  export POE_BASE_URL="${POE_BASE_URL:-https://api.poe.com}"
  export POE_API_KEY
  mapfile -t cmd < <(build_claw_command "$CLAW_MODEL" -p "$prompt" "$@")
  exec "${cmd[@]}"
}

sanitize_alias_component() {
  local value="$1"
  value="${value// /-}"
  value="${value//\//-}"
  value="${value//:/-}"
  value="${value//[^A-Za-z0-9._-]/-}"
  while [[ "$value" == *--* ]]; do
    value="${value//--/-}"
  done
  value="${value#-}"
  value="${value%-}"
  if [[ -z "$value" ]]; then
    value="model"
  fi
  printf '%s\n' "$value"
}

prepare_local_model_alias() {
  local model_ref="$1"
  local alias_name="$2"

  if [[ ! -e "$model_ref" ]]; then
    echo "Local model path does not exist: $model_ref" >&2
    exit 1
  fi

  local alias_path="$ROOT_DIR/$alias_name"
  if [[ -e "$alias_path" && ! -L "$alias_path" ]]; then
    echo "Refusing to replace non-symlink path: $alias_path" >&2
    exit 1
  fi

  ln -sfn "$model_ref" "$alias_path"
}

resolve_local_model_id_from_ref() {
  local model_ref="$1"

  if [[ -e "$model_ref" ]]; then
    local alias_name="$LOCAL_MODEL_ALIAS"
    if [[ "$model_ref" != "$LOCAL_MODEL_REF" ]]; then
      alias_name="${LOCAL_MODEL_ALIAS}-$(sanitize_alias_component "$(basename "$model_ref")")"
    fi
    prepare_local_model_alias "$model_ref" "$alias_name"
    printf '%s\n' "$alias_name"
    return 0
  fi

  printf '%s\n' "$model_ref"
}

ensure_local_state_dir() {
  mkdir -p "$(dirname "$LOCAL_SERVER_STATE_FILE")"
}

write_local_server_state() {
  local host="$1"
  local port="$2"
  local base_url="$3"
  local model_id="$4"
  local model_ref="$5"

  ensure_local_state_dir
  cat >"$LOCAL_SERVER_STATE_FILE" <<EOF
LOCAL_SERVER_STATE_HOST=$host
LOCAL_SERVER_STATE_PORT=$port
LOCAL_SERVER_STATE_BASE_URL=$base_url
LOCAL_SERVER_STATE_MODEL_ID=$model_id
LOCAL_SERVER_STATE_MODEL_REF=$model_ref
EOF
}

load_local_server_state() {
  if [[ -f "$LOCAL_SERVER_STATE_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$LOCAL_SERVER_STATE_FILE"
    set +a
    return 0
  fi
  return 1
}

tcp_port_in_use() {
  local host="$1"
  local port="$2"
  if (echo >"/dev/tcp/$host/$port") >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

healthcheck_url() {
  local base_url="$1"
  printf '%s\n' "${base_url%/v1}/health"
}

base_url_is_healthy() {
  local base_url="$1"
  curl -fsS --max-time 2 "$(healthcheck_url "$base_url")" >/dev/null 2>&1
}

resolve_configured_local_base_url() {
  printf 'http://%s:%s/v1\n' "$LOCAL_SERVER_HOST" "$LOCAL_SERVER_PORT"
}

resolve_local_base_url() {
  if load_local_server_state && [[ -n "${LOCAL_SERVER_STATE_BASE_URL:-}" ]]; then
    if base_url_is_healthy "$LOCAL_SERVER_STATE_BASE_URL"; then
      printf '%s\n' "$LOCAL_SERVER_STATE_BASE_URL"
      return 0
    fi
  fi

  resolve_configured_local_base_url
}

resolve_local_model_id() {
  if [[ -n "$LOCAL_MODEL_REQUEST" ]]; then
    resolve_local_model_id_from_ref "$LOCAL_MODEL_REQUEST"
    return 0
  fi

  if load_local_server_state && [[ -n "${LOCAL_SERVER_STATE_MODEL_ID:-}" ]]; then
    if [[ -n "${LOCAL_SERVER_STATE_BASE_URL:-}" ]] && base_url_is_healthy "$LOCAL_SERVER_STATE_BASE_URL"; then
      printf '%s\n' "$LOCAL_SERVER_STATE_MODEL_ID"
      return 0
    fi
  fi

  resolve_local_model_id_from_ref "$LOCAL_MODEL_REF"
}

resolve_local_server_port() {
  local desired_port="$LOCAL_SERVER_PORT"
  local max_offset="$LOCAL_SERVER_PORT_SEARCH_LIMIT"
  local offset=0

  while (( offset <= max_offset )); do
    local candidate=$((desired_port + offset))
    if ! tcp_port_in_use "$LOCAL_SERVER_HOST" "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    offset=$((offset + 1))
  done

  echo "Unable to find a free local server port starting from $LOCAL_SERVER_PORT" >&2
  exit 1
}

local_server_flags=()
if [[ "$LOCAL_SERVER_ENABLE_CORS" == "true" ]]; then
  local_server_flags+=(--enable-cors)
fi
if [[ "$LOCAL_SERVER_CONTINUOUS_BATCHING" == "true" ]]; then
  local_server_flags+=(--continuous-batching)
fi

run_local_server() {
  parse_local_launcher_args "$@"
  require_cmd conda
  require_cmd curl
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL POE_API_KEY POE_BASE_URL XAI_API_KEY XAI_BASE_URL
  local conda_env_prefix
  conda_env_prefix="$(resolve_conda_env_prefix)"
  local model_id
  model_id="$(resolve_local_model_id)"
  if load_local_server_state \
    && [[ "${LOCAL_SERVER_STATE_MODEL_ID:-}" == "$model_id" ]] \
    && [[ -n "${LOCAL_SERVER_STATE_BASE_URL:-}" ]] \
    && base_url_is_healthy "$LOCAL_SERVER_STATE_BASE_URL"; then
    echo "Local server already running"
    echo "  Model            $LOCAL_SERVER_STATE_MODEL_ID"
    echo "  Base URL         $LOCAL_SERVER_STATE_BASE_URL"
    echo "  State file       $LOCAL_SERVER_STATE_FILE"
    return 0
  fi
  local server_port
  server_port="$(resolve_local_server_port)"
  local base_url
  base_url="http://$LOCAL_SERVER_HOST:$server_port/v1"
  write_local_server_state "$LOCAL_SERVER_HOST" "$server_port" "$base_url" "$model_id" "${LOCAL_MODEL_REQUEST:-$LOCAL_MODEL_REF}"
  echo "Starting local server"
  echo "  Model            $model_id"
  echo "  Base URL         $base_url"
  echo "  Conda env        $conda_env_prefix"
  echo "  State file       $LOCAL_SERVER_STATE_FILE"
  exec conda run -p "$conda_env_prefix" transformers serve \
    --host "$LOCAL_SERVER_HOST" \
    --port "$server_port" \
    --device "$LOCAL_SERVER_DEVICE" \
    --dtype "$LOCAL_SERVER_DTYPE" \
    --force-model "$model_id" \
    "${local_server_flags[@]}" \
    "${LOCAL_LAUNCHER_ARGS[@]}"
}

run_local_cli() {
  parse_local_launcher_args "$@"
  ensure_cargo_env
  require_cmd curl
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL POE_API_KEY POE_BASE_URL XAI_API_KEY XAI_BASE_URL
  local model_id
  model_id="$(resolve_local_model_id)"
  local base_url
  base_url="$(resolve_local_base_url)"
  if ! base_url_is_healthy "$base_url"; then
    echo "Local server is not reachable at $base_url" >&2
    echo "Start it first with: claw-local-server" >&2
    exit 1
  fi
  if (( LOCAL_MODEL_WAS_EXPLICIT )) \
    && load_local_server_state \
    && [[ -n "${LOCAL_SERVER_STATE_MODEL_ID:-}" ]] \
    && [[ -n "${LOCAL_SERVER_STATE_BASE_URL:-}" ]] \
    && base_url_is_healthy "$LOCAL_SERVER_STATE_BASE_URL" \
    && [[ "$LOCAL_SERVER_STATE_MODEL_ID" != "$model_id" ]]; then
    echo "The active local server is serving $LOCAL_SERVER_STATE_MODEL_ID, not $model_id" >&2
    echo "Start a matching server first with: claw-local-server --local-model $LOCAL_MODEL_REQUEST" >&2
    exit 1
  fi
  export OPENAI_API_KEY="${OPENAI_API_KEY:-local-test-key}"
  export OPENAI_BASE_URL="$base_url"
  if ! has_claw_arg "--allowedTools" "${LOCAL_LAUNCHER_ARGS[@]}" \
    && ! has_claw_arg "--allowed-tools" "${LOCAL_LAUNCHER_ARGS[@]}" \
    && [[ -n "$LOCAL_ALLOWED_TOOLS" ]]; then
    LOCAL_LAUNCHER_ARGS=(--allowedTools "$LOCAL_ALLOWED_TOOLS" "${LOCAL_LAUNCHER_ARGS[@]}")
  fi
  if (( LOCAL_MODEL_WAS_EXPLICIT )); then
    LOCAL_LAUNCHER_ARGS=(--model "$model_id" "${LOCAL_LAUNCHER_ARGS[@]}")
  fi
  mapfile -t cmd < <(build_claw_command "$model_id" "${LOCAL_LAUNCHER_ARGS[@]}")
  exec "${cmd[@]}"
}

run_local_prompt() {
  local prompt="${1:-$CLAW_DEFAULT_PROMPT}"
  shift || true
  parse_local_launcher_args "$@"
  ensure_cargo_env
  require_cmd curl
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL POE_API_KEY POE_BASE_URL XAI_API_KEY XAI_BASE_URL
  local model_id
  model_id="$(resolve_local_model_id)"
  local base_url
  base_url="$(resolve_local_base_url)"
  if ! base_url_is_healthy "$base_url"; then
    echo "Local server is not reachable at $base_url" >&2
    echo "Start it first with: claw-local-server" >&2
    exit 1
  fi
  if (( LOCAL_MODEL_WAS_EXPLICIT )) \
    && load_local_server_state \
    && [[ -n "${LOCAL_SERVER_STATE_MODEL_ID:-}" ]] \
    && [[ -n "${LOCAL_SERVER_STATE_BASE_URL:-}" ]] \
    && base_url_is_healthy "$LOCAL_SERVER_STATE_BASE_URL" \
    && [[ "$LOCAL_SERVER_STATE_MODEL_ID" != "$model_id" ]]; then
    echo "The active local server is serving $LOCAL_SERVER_STATE_MODEL_ID, not $model_id" >&2
    echo "Start a matching server first with: claw-local-server --local-model $LOCAL_MODEL_REQUEST" >&2
    exit 1
  fi
  export OPENAI_API_KEY="${OPENAI_API_KEY:-local-test-key}"
  export OPENAI_BASE_URL="$base_url"
  if ! has_claw_arg "--allowedTools" "${LOCAL_LAUNCHER_ARGS[@]}" \
    && ! has_claw_arg "--allowed-tools" "${LOCAL_LAUNCHER_ARGS[@]}" \
    && [[ -n "$LOCAL_ALLOWED_TOOLS" ]]; then
    LOCAL_LAUNCHER_ARGS=(--allowedTools "$LOCAL_ALLOWED_TOOLS" "${LOCAL_LAUNCHER_ARGS[@]}")
  fi
  if (( LOCAL_MODEL_WAS_EXPLICIT )); then
    LOCAL_LAUNCHER_ARGS=(--model "$model_id" "${LOCAL_LAUNCHER_ARGS[@]}")
  fi
  mapfile -t cmd < <(build_claw_command "$model_id" -p "$prompt" "${LOCAL_LAUNCHER_ARGS[@]}")
  exec "${cmd[@]}"
}

main() {
  case "$INVOKED_AS" in
    claw)
      if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        return 0
      fi
      if [[ "$CLAW_PROVIDER" == "local" ]]; then
        run_local_cli "$@"
      else
        run_poe_cli "$@"
      fi
      return 0
      ;;
    claw-local)
      run_local_cli "$@"
      return 0
      ;;
    claw-poe)
      run_poe_cli "$@"
      return 0
      ;;
    claw-local-server)
      run_local_server "$@"
      return 0
      ;;
    claw-doctor)
      doctor
      return 0
      ;;
  esac

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    help|-h|--help)
      usage
      ;;
    doctor)
      doctor
      ;;
    build)
      build_claw
      ;;
    poe-cli)
      run_poe_cli "$@"
      ;;
    poe-prompt)
      run_poe_prompt "$@"
      ;;
    local-server)
      run_local_server "$@"
      ;;
    local-cli)
      run_local_cli "$@"
      ;;
    local-prompt)
      run_local_prompt "$@"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
