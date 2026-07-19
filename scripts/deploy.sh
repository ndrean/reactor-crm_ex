#!/usr/bin/env bash
set -euo pipefail

# Deploy CRM Reactor to Docker Swarm
# Usage: ./scripts/deploy.sh [--build] [--migrate] [--secrets-from .env-docker]

STACK_NAME="crm"
IMAGE_NAME="crm_reactor:latest"
STACK_FILE="docker-stack.yml"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --build                Build the Docker image
  --migrate              Run database migrations after deploy
  --secrets-from FILE    Create Docker secrets from env file (e.g., .env-docker)
  --help                 Show this help

Examples:
  # First-time setup
  $0 --build --secrets-from .env-docker --migrate

  # Subsequent deploys
  $0 --build --migrate

  # Just redeploy (image already built)
  $0
EOF
}

build_image() {
  echo "==> Building image: $IMAGE_NAME"
  if [[ "$NO_CACHE" == true ]]; then
    docker build --no-cache -t "$IMAGE_NAME" .
  else
    docker build -t "$IMAGE_NAME" .
  fi
}

create_secrets() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    echo "Error: $env_file not found"
    exit 1
  fi

  echo "==> Creating Docker secrets from $env_file"

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Split on first '=' only
    key="${line%%=*}"
    value="${line#*=}"

    # Remove surrounding quotes from value
    value="${value%\"}"
    value="${value#\"}"

    # Map env var name to Docker secret name
    local secret_name=""
    case "$key" in
      DATABASE_URL)         secret_name="database_url" ;;
      SECRET_KEY_BASE)      secret_name="secret_key_base" ;;
      MISTRAL_API_KEY)      secret_name="mistral_api_key" ;;
      CLOAK_KEY)            secret_name="cloak_key" ;;
      ADMIN_TOKEN)          secret_name="admin_token" ;;
      TELEGRAM_BOT_TOKEN)   secret_name="telegram_bot_token" ;;
      TELEGRAM_SECRET_TOKEN) secret_name="telegram_secret_token" ;;
      POSTGRES_USER)        secret_name="postgres_user" ;;
      POSTGRES_PASSWORD)    secret_name="postgres_password" ;;
    esac

    if [[ -n "$secret_name" ]]; then
      docker secret rm "$secret_name" 2>/dev/null || true
      echo -n "$value" | docker secret create "$secret_name" - \
        && echo "  Created secret: $secret_name" \
        || echo "  Warning: failed to create secret: $secret_name"
    fi
  done < "$env_file"
}

remove_existing_stack() {
  if docker stack ps "$STACK_NAME" >/dev/null 2>&1; then
    echo "==> Removing existing stack: $STACK_NAME"
    docker stack rm "$STACK_NAME"
    echo "  Waiting for stack to fully stop..."
    while docker stack ps "$STACK_NAME" >/dev/null 2>&1; do
      sleep 2
    done
    # Wait for containers to actually stop (Swarm has a delay after task removal)
    echo "  Waiting for containers to stop..."
    local wait_attempts=0
    while [[ $wait_attempts -lt 30 ]]; do
      local remaining
      remaining=$(docker ps -q --filter "label=com.docker.stack.namespace=${STACK_NAME}" 2>/dev/null)
      if [[ -z "$remaining" ]]; then
        break
      fi
      if [[ $wait_attempts -eq 10 ]]; then
        echo "  Force-killing stuck containers..."
        docker kill $remaining 2>/dev/null || true
      fi
      sleep 2
      wait_attempts=$((wait_attempts + 1))
    done
    # Final cleanup of any remaining containers
    local orphans
    orphans=$(docker ps -aq --filter "label=com.docker.stack.namespace=${STACK_NAME}" 2>/dev/null)
    if [[ -n "$orphans" ]]; then
      docker rm -f $orphans 2>/dev/null || true
    fi
    echo "  Stack removed."
  fi
}

deploy_stack() {
  remove_existing_stack
  echo "==> Deploying stack: $STACK_NAME"
  CRM_IMAGE="$IMAGE_NAME" docker stack deploy -c "$STACK_FILE" "$STACK_NAME"
  echo "==> Stack deployed. Checking services..."
  docker service ls --filter "name=${STACK_NAME}_"
}

run_migration() {
  echo "==> Running migrations..."
  docker service scale "${STACK_NAME}_migrate=1" --detach

  # Wait for migration to complete (poll task state)
  echo "  Waiting for migration to finish..."
  local attempts=0
  while [[ $attempts -lt 60 ]]; do
    local state
    state=$(docker service ps "${STACK_NAME}_migrate" --format '{{.CurrentState}}' --filter 'desired-state=shutdown' 2>/dev/null | head -1)
    if [[ "$state" == *"Complete"* ]]; then
      echo "  Migration completed successfully."
      docker service scale "${STACK_NAME}_migrate=0" --detach
      return 0
    elif [[ "$state" == *"Failed"* || "$state" == *"Rejected"* ]]; then
      echo "  ERROR: Migration failed. Check logs:"
      echo "    docker service logs ${STACK_NAME}_migrate"
      docker service scale "${STACK_NAME}_migrate=0" --detach
      return 1
    fi
    sleep 2
    attempts=$((attempts + 1))
  done

  echo "  WARNING: Migration timed out after 120s. Check logs:"
  echo "    docker service logs ${STACK_NAME}_migrate"
  docker service scale "${STACK_NAME}_migrate=0" --detach
  return 1
}

# Parse arguments
DO_BUILD=false
DO_MIGRATE=false
NO_CACHE=false
SECRETS_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --build) DO_BUILD=true; shift ;;
    --no-cache) NO_CACHE=true; shift ;;
    --migrate) DO_MIGRATE=true; shift ;;
    --secrets-from) SECRETS_FILE="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Initialize swarm if needed
if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
  echo "==> Initializing Docker Swarm..."
  docker swarm init
fi

# Execute steps
[[ "$DO_BUILD" == true ]] && build_image
[[ -n "$SECRETS_FILE" ]] && create_secrets "$SECRETS_FILE"
deploy_stack
[[ "$DO_MIGRATE" == true ]] && run_migration

echo ""
echo "==> Done! Useful commands:"
echo "  docker service ls                          # List services"
echo "  docker service logs -f ${STACK_NAME}_app   # Follow app logs"
echo "  docker service ps ${STACK_NAME}_app        # Show replica status"
echo "  docker stack rm $STACK_NAME                # Remove stack"
