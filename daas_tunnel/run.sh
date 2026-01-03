#!/bin/sh
set -e

#####################################
# Structured JSON logger
#####################################
log() {
  level="$1"; shift
  event="$1"; shift
  msg="$1"; shift

  kv=""
  while [ $# -gt 1 ]; do
    kv="$kv,\"$1\":\"$2\""
    shift 2
  done

  echo "{\"ts\":\"$(date -Is)\",\"level\":\"$level\",\"component\":\"daas_tunnel\",\"event\":\"$event\",\"msg\":\"$msg\"$kv}"
}

#####################################
# Boot/session identifier
#####################################
BOOT_ID="$(cat /proc/sys/kernel/random/uuid)"
log INFO addon_start "DAAS tunnel add-on starting" boot_id "$BOOT_ID"

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

log INFO config_loaded "Configuration loaded" server "$SERVER" user "$USER" remote_port "$REMOTE_PORT"

#####################################
# SSH key handling (NO SPAM)
#####################################
if [ ! -f "$KEY_PATH" ]; then
  log WARN key_missing "SSH key missing, generating new keypair"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "daas-tunnel@$(hostname)" >/dev/null 2>&1
  chmod 600 "$KEY_PATH"

  log INFO key_generated "SSH key generated; install this public key on the server and restart the add-on" \
    pubkey "$(cat "$PUB_PATH")"

  # Exit cleanly so we do NOT spam auth failures
  exit 0
fi

#####################################
# SSH command definition
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
# Retry loop with classification
#####################################
attempt=0
backoff=5

while true; do
  attempt=$((attempt + 1))
  log INFO ssh_connecting "Attempting SSH tunnel" attempt "$attempt" backoff_sec "$backoff"

  run_ssh 2> >(while IFS= read -r line; do
    case "$line" in
      *"Permission denied (publickey)"*)
        log ERROR ssh_auth_failed "$line" action "install_public_key_on_server"
        ;;
      *"remote port forwarding failed for listen port"*)
        log ERROR port_forward_failed "$line" action "check_port_in_use_or_permitopen"
        ;;
      *"Broken pipe"*|*"Connection reset"*|*"timed out"*)
        log WARN ssh_disconnected "$line" recovering "true"
        ;;
      *"Permanently added"*|*"known hosts"*)
        log INFO ssh_known_host "$line"
        ;;
      *)
        log INFO ssh "$line"
        ;;
    esac
  done)

  log WARN ssh_exit "SSH tunnel exited; retrying" attempt "$attempt"

  sleep "$backoff"
  [ "$backoff" -lt 60 ] && backoff=$((backoff * 2))
done
