#!/bin/bash
# Shared helpers for Vigil startup scripts.
# Source this file: source scripts/lib.sh

# Determine docker compose command (v2 plugin vs v1 standalone)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Ensure a service is listening on the expected port, starting it via Docker
# if needed. Skips Docker if something is already listening.
#
# Usage: ensure_service <name> <port> <compose_service> [compose_env_var]
#   name:             display name (e.g. "PostgreSQL")
#   port:             port to check / expose
#   compose_service:  docker compose service name (e.g. "postgres")
#   compose_env_var:  env var to pass port to compose (e.g. "POSTGRES_PORT")
#   wait_cmd:         optional command to poll readiness (run inside container)
ensure_service() {
    local name="$1"
    local port="$2"
    local compose_service="$3"
    local compose_env_var="$4"
    local container_name="$5"
    local wait_cmd="$6"

    echo ""
    echo "Checking ${name}..."

    # Already listening locally — skip Docker entirely
    if ss -tln | grep -q ":${port} "; then
        echo "✓ ${name} already listening on port ${port} (skipping Docker)"
        return 0
    fi

    if ! command -v docker &> /dev/null; then
        echo "⚠️  No ${name} on port ${port} and Docker not found."
        return 1
    fi

    # Docker container already running
    if docker ps --format '{{.Names}}' | grep -q "${container_name}"; then
        echo "✓ ${name} container is already running"
        return 0
    fi

    echo "Starting ${name} via Docker (port ${port})..."
    cd docker
    eval "${compose_env_var}=${port} \$DOCKER_COMPOSE up -d ${compose_service}"
    cd ..

    # Wait for readiness if a check command was provided
    if [ -n "$wait_cmd" ]; then
        echo "Waiting for ${name}..."
        for i in {1..30}; do
            if eval "$wait_cmd" &> /dev/null 2>&1; then
                echo "✓ ${name} is ready!"
                return 0
            fi
            if [ $i -eq 30 ]; then
                echo "⚠️  ${name} may not be ready"
                return 1
            fi
            sleep 1
        done
    else
        sleep 2
        echo "✓ ${name} started"
    fi
    return 0
}

# Parse DATABASE_URL and REDIS_URL to extract ports.
# Sets DB_PORT and REDIS_PORT_NUM.
parse_service_ports() {
    DB_PORT=$(echo "$DATABASE_URL" | grep -oP ':(\d+)/' | tr -d ':/')
    DB_PORT="${DB_PORT:-5432}"
    REDIS_PORT_NUM=$(echo "$REDIS_URL" | grep -oP ':(\d+)/' | tr -d ':/')
    REDIS_PORT_NUM="${REDIS_PORT_NUM:-6379}"
}
