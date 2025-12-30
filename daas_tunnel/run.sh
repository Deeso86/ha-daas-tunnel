#!/bin/sh
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

