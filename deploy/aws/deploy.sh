#!/usr/bin/env bash
# Rolls out a new play image on the Hyperlabs Office EC2.
# Usage: deploy.sh <tag>   (called by .github/workflows/hyperlabs-deploy.yml through SSM, as root; also works by hand)
# Installed at /opt/hyper-office/deploy.sh. PLAY_IMAGE and PLAY_IMAGE_TAG live in /opt/hyper-office/.env.
set -euo pipefail

TAG="${1:?missing image tag}"
cd /opt/hyper-office

PLAY_IMAGE=$(grep '^PLAY_IMAGE=' .env | cut -d= -f2-)
PREV=$(grep '^PLAY_IMAGE_TAG=' .env | cut -d= -f2-)
set_tag() { sed -i "s|^PLAY_IMAGE_TAG=.*|PLAY_IMAGE_TAG=$1|" .env; }

echo "Deploying $PLAY_IMAGE:$TAG (previous: $PREV)"
set_tag "$TAG"
if ! docker compose pull play || ! docker compose up -d play; then
    echo "ERROR: could not start $TAG, rolling back to $PREV" >&2
    set_tag "$PREV"
    docker compose up -d play
    exit 1
fi

for _ in $(seq 1 36); do
    state=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q play)")
    if [ "$state" = healthy ]; then
        echo "OK: play $TAG is healthy"
        # Keep the 3 most recent play images for rollbacks, drop the older ones
        docker images "$PLAY_IMAGE" --format '{{.CreatedAt}}|{{.Repository}}:{{.Tag}}' | sort -r | tail -n +4 \
            | cut -d'|' -f2 | xargs -r docker rmi >/dev/null 2>&1 || true
        docker image prune -f >/dev/null
        exit 0
    fi
    sleep 5
done

echo "ERROR: play $TAG did not become healthy, rolling back to $PREV" >&2
set_tag "$PREV"
docker compose up -d play
exit 1
