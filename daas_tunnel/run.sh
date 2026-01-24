#!/bin/sh
set -e

#####################################
# Simple HA-style logger
#####################################
log() {
  level="$1"; shift
  echo "[$(date '+%Y-%m-%d  %H:%M:%S')] $level: $*"
}

#####################################
# Startup
#####################################
log INFO "DAAS tunnel add-on starting (pid=$SSH_PID user=$SSH_USER remote_port=$REMOTE_PORT)"

#####################################
# Paths and permissions
#####################################
KEY_DIR="/data/ssh"
KEY_PATH="$KEY_DIR/id_ed25519"
PUB_PATH="$KEY_PATH.pub"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

#####################################
# Read HA add-on options
#####################################
SERVER="$(jq -r '.server' /data/options.json)"
USER="$(jq -r '.user' /data/options.json)"
REMOTE_PORT="$(jq -r '.remote_port' /data/options.json)"
LOCAL_PORT="8123"

log INFO "Configuration loaded (server=$SERVER user=$USER remote_port=$REMOTE_PORT)"



# --- Clean shutdown handling (HA Supervisor) ---
trap '
  log INFO "Received SIGTERM, stopping tunnel"
  if [ -n "${SSH_PID:-}" ] && kill -0 "$SSH_PID" 2>/dev/null; then
    log INFO "Stopping SSH process (pid=$SSH_PID)"
    kill "$SSH_PID"
  fi
  exit 0
' TERM INT


#####################################
# SSH key handling (clean & quiet)
#####################################
if [ ! -f "$KEY_PATH" ]; then
  log WARNING "SSH key not found, generating new keypair"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "daas-tunnel@$(hostname)" >/dev/null 2>&1
  chmod 600 "$KEY_PATH"

  log INFO "SSH key generated"
  log INFO "Install the following public key on the server and restart the add-on:"
  echo "--------------------------------------------------"
  cat "$PUB_PATH"
  echo "--------------------------------------------------"

  exit 0
fi

#####################################
# SSH command
#####################################
run_ssh() {
  autossh \
    -M 0 \
    -N \
    -i "$KEY_PATH" \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=accept-new \
    -R "127.0.0.1:${REMOTE_PORT}:localhost:${LOCAL_PORT}" \
    "${USER}@${SERVER}"
}

#####################################
# Retry loop with clear status
#####################################
attempt=0
backoff=5

while true; do
  attempt=$((attempt + 1))
  log INFO "Connecting to SSH server (attempt $attempt)"
	# --- Safety: ensure no previous SSH process is still running ---
  if [ -n "${SSH_PID:-}" ] && kill -0 "$SSH_PID" 2>/dev/null; then
    log WARNING "Previous SSH process still running (pid=$SSH_PID), skipping restart"
    sleep 10
    continue
  fi
    run_ssh \
      > >(while IFS= read -r line; do
          log INFO "$line"
        done) \
      2> >(while IFS= read -r line; do
          case "$line" in
            *"Permission denied (publickey)"*)
              log ERROR "SSH authentication failed (public key not accepted)"
              ;;
            *"remote port forwarding failed for listen port"*)
              log ERROR "Remote port forwarding failed (check port collision or server config)"
              ;;
            *"Broken pipe"*|*"Connection reset"*|*"timed out"*)
              log WARNING "SSH disconnected ($line)"
              ;;
            *"Permanently added"*)
              log INFO "SSH host key accepted"
              ;;
            *)
              log INFO "$line"
              ;;
          esac
        done) &

  SSH_PID=$!

  # Give SSH time to fail if it will
  sleep 2

  if kill -0 "$SSH_PID" 2>/dev/null; then
    log INFO "Tunnel established successfully (pid=$SSH_PID remote_port=$REMOTE_PORT)"
    wait "$SSH_PID"
    log WARNING "Tunnel closed, reconnecting (pid=$SSH_PID exit_code=$?)"
  else
    log ERROR "SSH exited before tunnel could establish"
  fi

  log INFO "Retrying in ${backoff}s"
  sleep "$backoff"
  [ "$backoff" -lt 60 ] && backoff=$((backoff * 2))
done
