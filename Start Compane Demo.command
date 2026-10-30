#!/bin/bash
# Double-click to start the Compane ER demo. Needs Docker Desktop installed.
cd "$(dirname "$0")" || exit 1

pause_and_exit() { echo; read -r -p "Press Enter to close this window." _; exit "$1"; }

echo "Starting the Compane ER demo..."

# 1. Make sure Docker Desktop is running
if ! docker info >/dev/null 2>&1; then
  echo "Opening Docker Desktop..."
  open -a Docker 2>/dev/null || { echo "Docker Desktop is not installed. Install it from docker.com, then try again."; pause_and_exit 1; }
  for _ in $(seq 1 90); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || { echo "Docker Desktop did not start. Open it yourself, wait until it says running, then try again."; pause_and_exit 1; }
fi

# 2. If the database design changed since last time, start with a fresh database
VERSION=$(cat db/*.sql | shasum | cut -d' ' -f1)
if [ ! -f .db-version ] || [ "$(cat .db-version)" != "$VERSION" ]; then
  echo "The database design changed, so the demo data is being reset..."
  docker compose down -v
fi

# 3. Build and start everything in the background
if ! docker compose up -d --build; then
  echo
  echo "Something went wrong while starting. The database's own messages:"
  docker compose logs --tail 30 db
  pause_and_exit 1
fi
echo "$VERSION" > .db-version

# 4. Wait until the screens and the API answer, then open the browser
echo "Waiting for the demo to be ready (the first time takes a few minutes)..."
for _ in $(seq 1 150); do
  curl -sf http://localhost:3000/api/meta >/dev/null 2>&1 && break
  sleep 2
done
if curl -sf http://localhost:3000/api/meta >/dev/null 2>&1; then
  open http://localhost:3000
  echo
  echo "The demo is running at http://localhost:3000"
  echo "You can close this window. To stop the demo, quit Docker Desktop."
  pause_and_exit 0
else
  echo "The demo did not answer in time. Open Docker Desktop to see what happened."
  pause_and_exit 1
fi
