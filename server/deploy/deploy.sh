#!/bin/sh
# Builds the server for Linux and installs it on a host with systemd.
#   OPENTODO_HOST=<ssh host> ./deploy/deploy.sh            update the binary and restart
#   OPENTODO_HOST=<ssh host> ./deploy/deploy.sh --setup    first time: user, folders, systemd units
# The Caddy site block (Caddyfile.snippet) is added by hand once.
set -eu
HOST=${OPENTODO_HOST:?set OPENTODO_HOST to the ssh host to deploy to}
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o "$out/opentodo-server" ./cmd/opentodo-server
scp -q "$out/opentodo-server" deploy/opentodo.service deploy/opentodo-backup.service deploy/opentodo-backup.timer "$HOST:/tmp/"

ssh "$HOST" SETUP="${1:-}" sh -s <<'REMOTE'
set -eu
if [ "$SETUP" = "--setup" ]; then
  id opentodo >/dev/null 2>&1 || sudo useradd --system --home-dir /var/lib/opentodo --no-create-home --shell /usr/sbin/nologin opentodo
  sudo install -d -o root -g root -m 0755 /opt/opentodo
  sudo install -d -o opentodo -g opentodo -m 0750 /var/lib/opentodo /var/lib/opentodo/backups
fi
sudo install -o root -g root -m 0755 /tmp/opentodo-server /opt/opentodo/opentodo-server
for u in opentodo.service opentodo-backup.service opentodo-backup.timer; do
  sudo install -o root -g root -m 0644 /tmp/$u /etc/systemd/system/$u
done
rm -f /tmp/opentodo-server /tmp/opentodo.service /tmp/opentodo-backup.service /tmp/opentodo-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now opentodo-backup.timer >/dev/null
sudo systemctl enable opentodo.service >/dev/null
sudo systemctl restart opentodo.service
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1:8686/v1/health >/dev/null 2>&1; then echo "opentodo is up"; exit 0; fi
  sleep 1
done
echo "opentodo did not come up:" >&2
sudo journalctl -u opentodo.service -n 30 --no-pager >&2
exit 1
REMOTE
