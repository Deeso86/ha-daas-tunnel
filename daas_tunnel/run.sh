#!/bin/sh
set -e

SERVER=$(jq -r '.server' /data/options.json)
USER=$(jq -r '.user' /data/options.json)
PORT=$(jq -r '.remote_port' /data/options.json)

echo "Starting DAAS tunnel to $SERVER on port $PORT"

exec autossh \
  -M 0 \
  -N \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o StrictHostKeyChecking=no \
  -R 127.0.0.1:${PORT}:localhost:8123 \
  ${USER}@${SERVER}
