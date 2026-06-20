#!/usr/bin/env bash

set -euo pipefail

: "${DEPLOY_PATH:?DEPLOY_PATH is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${RELEASE_COMMIT:?RELEASE_COMMIT is required}"
ENV_FILE="${ENV_FILE:-/home/secrets/.env}"

cd "$DEPLOY_PATH"
test -f "$ENV_FILE"
test -d .git

git config --global --add safe.directory "$DEPLOY_PATH" 2>/dev/null || true

git fetch --all --tags --prune
git checkout -f "$RELEASE_COMMIT"

actual_commit="$(git rev-parse HEAD)"
if [[ "$actual_commit" != "$RELEASE_COMMIT" ]]; then
  echo "Expected commit $RELEASE_COMMIT but checked out $actual_commit"
  exit 1
fi

export RELEASE_TAG

docker compose -f docker-compose.yml --env-file "$ENV_FILE" build frontend backend
docker compose -f docker-compose.yml --env-file "$ENV_FILE" up -d --no-build --force-recreate frontend backend

for attempt in {1..30}; do
  backend_status="$(
    docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      mern-backend 2>/dev/null || true
  )"
  frontend_status="$(
    docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      mern-frontend 2>/dev/null || true
  )"

  if [[ "$backend_status" == "healthy" && "$frontend_status" == "healthy" ]]; then
    docker image prune -f
    exit 0
  fi

  sleep 5
done

docker compose -f docker-compose.yml --env-file "$ENV_FILE" ps
docker compose -f docker-compose.yml --env-file "$ENV_FILE" logs --tail 100 backend frontend
exit 1
