#!/bin/sh
log() {
  local level="$1"; shift
  local event="$1"; shift
  local msg="$1"; shift

  # Optional k=v pairs after msg
  local kv=""
  while [ $# -gt 0 ]; do
    kv="$kv,\"$1\":\"$2\""
    shift 2
  done

  echo "{\"ts\":\"$(date -Is)\",\"level\":\"$level\",\"component\":\"daas_tunnel\",\"event\":\"$event\",\"msg\":\"$msg\"$kv}"
}

BOOT_ID="$(cat /proc/sys/kernel/random/uuid)"
log INFO addon_start "DAAS tunnel add-on starting" boot_id "$BOOT_ID"



set -e

KEY_PATH="/data/ssh/id_ed25519"

mkdir -p /data/ssh
chmod 700 /data/ssh

if [ ! -f "$KEY_PATH" ]; then
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
  echo "Public key:"
  cat "$KEY_PATH.pub"
fi

SERVER=$(jq -r '.server' /data/options.json)
USER=$(jq -r '.user' /data/options.json)
PORT=$(jq -r '.remote_port' /data/options.json)

exec autossh \
  -M 0 \
  -N \
  -i "$KEY_PATH" \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o StrictHostKeyChecking=no \
  -R 127.0.0.1:${PORT}:localhost:8123 \
  ${USER}@${SERVER}

