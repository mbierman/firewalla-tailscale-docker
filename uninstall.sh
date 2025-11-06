#!/bin/bash

# 🗑️ Tailscale Docker Uninstaller for Firewalla 🗑️

# --- Configuration ---
DOCKER_DIR="/home/pi/.firewalla/run/docker/tailscale"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
STATE_DIR="$DOCKER_DIR/ts-firewalla/state"
CONFIG_DIR="$DOCKER_DIR/ts-firewalla/config"
UNINSTALL_SCRIPT_PATH="/data/uninstall-tailscale-firewalla.sh"

# --- Options ---
TEST_MODE=false
CONFIRM_MODE=false

while getopts "tc" opt; do
  case $opt in
    t)
      TEST_MODE=true
      ;;
    c)
      CONFIRM_MODE=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# --- Functions ---

log_info() {
    echo "ℹ️ $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

log_warning() {
    echo "⚠️ $1"
}

run_cmd() {
    if [ "$TEST_MODE" = true ]; then
        echo "DRY RUN: Would execute: $@"
        return 0 # Assume success in test mode
    fi

    if [ "$CONFIRM_MODE" = true ]; then
        read -p "Execute '$@'? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Skipping command."
            return 1 # Indicate skipped
        fi
    fi

    "$@"
}

# --- Pre-checks ---

log_info "Starting Tailscale Docker uninstallation for Firewalla..."

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Cannot proceed with uninstallation."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed. Cannot proceed with uninstallation."
    exit 1
fi

# --- Stop and Remove Container ---

if [ -f "$COMPOSE_FILE" ]; then
    log_info "Stopping and removing Tailscale container..."
    cd "$DOCKER_DIR" || { log_error "Failed to change directory to $DOCKER_DIR."; exit 1; }
    run_cmd sudo docker-compose down || { log_error "Failed to stop and remove Tailscale container."; }
    log_success "Tailscale container stopped and removed."
else
    log_warning "docker-compose.yml not found at $COMPOSE_FILE. Skipping container removal."
fi

# --- Remove Docker Image ---
log_info "Removing Tailscale Docker image..."
run_cmd sudo docker image rm tailscale/tailscale:latest || { log_warning "Failed to remove Tailscale Docker image. It may have already been removed or is in use by another container."; }
log_success "Tailscale Docker image removed."

# --- Disable IP Forwarding ---

log_info "Disabling IP forwarding..."
run_cmd sudo rm /etc/sysctl.d/99-tailscale.conf
log_success "IP forwarding disabled."

# --- Remove Files and Directories ---

log_info "Removing Tailscale related files and directories..."

if [ -f "$COMPOSE_FILE" ]; then
    run_cmd sudo rm "$COMPOSE_FILE" || { log_error "Failed to remove $COMPOSE_FILE."; }
    log_success "Removed $COMPOSE_FILE."
fi

if [ -d "$STATE_DIR" ]; then
    run_cmd sudo rm -rf "$STATE_DIR" || { log_error "Failed to remove $STATE_DIR."; }
    log_success "Removed $STATE_DIR."
fi

if [ -d "$CONFIG_DIR" ]; then
    run_cmd sudo rm -rf "$CONFIG_DIR" || { log_error "Failed to remove $CONFIG_DIR."; }
    log_success "Removed $CONFIG_DIR."
fi

if [ -d "$DOCKER_DIR" ]; then
    # Check if the directory is empty before removing it
    if [ -z "$(ls -A "$DOCKER_DIR")" ]; then
        run_cmd sudo rm -rf "$DOCKER_DIR" || { log_error "Failed to remove $DOCKER_DIR."; }
        log_success "Removed $DOCKER_DIR."
    else
        log_warning "$DOCKER_DIR is not empty after removing Tailscale files. Skipping directory removal."
    fi
fi

if [ -f "$UNINSTALL_SCRIPT_PATH" ]; then
    run_cmd sudo rm "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to remove $UNINSTALL_SCRIPT_PATH."; }
    log_success "Removed $UNINSTALL_SCRIPT_PATH."
fi

log_info "🗑️ Uninstallation Complete! 🗑️"
log_info "Tailscale Docker components have been removed from your Firewalla."
