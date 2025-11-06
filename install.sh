#!/bin/bash

version="1.0.0"
# Credit to u/adrianmihalko for the original docker-compose concept
# https://www.reddit.com/r/firewalla/comments/1mlrtvi/easy_tailscale_integration_via_docker_compose/

# 🚀 Tailscale Docker Installer for Firewalla 🚀

# --- Configuration ---
DOCKER_DIR="/home/pi/.firewalla/run/docker/tailscale"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
STATE_DIR="$DOCKER_DIR/ts-firewalla/state"
CONFIG_DIR="$DOCKER_DIR/ts-firewalla/config"
UNINSTALL_SCRIPT_PATH="/data/uninstall-tailscale-firewalla.sh"
# This URL will be updated to your GitHub raw URL once the repo is set up
UNINSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/uninstall.sh"

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
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

log_warning() {
    echo "⚠️  $1"
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

log_info "Starting Tailscale Docker installation for Firewalla..."

# --- Create Directories ---

log_info "Creating necessary directories..."
run_cmd sudo mkdir -p "$STATE_DIR" "$CONFIG_DIR" || { log_error "Failed to create directories."; exit 1; }
log_success "Directories created: $STATE_DIR and $CONFIG_DIR"

# --- Get User Input ---

log_info "Please provide the following information for Tailscale configuration:"

log_info "You can generate a reusable Auth Key from your Tailscale admin console."
log_info "See: https://tailscale.com/kb/1085/auth-keys/"

read -p "🔑 Enter your Tailscale Auth Key (e.g., tskey-auth-xxxxxxxxxxxxx): " TS_AUTHKEY
if [ -z "$TS_AUTHKEY" ]; then
    log_error "Tailscale Auth Key cannot be empty. Exiting."
    exit 1
fi

TS_EXTRA_ARGS=""

log_info "Before proceeding, please open your Firewalla app and go to Network Manager to identify the names of your networks (LAN, Guest, IoT, etc.) and their corresponding subnets. This will help you decide which subnets to advertise."

# --- Advertise Subnets ---
log_info "Detecting local subnets..."

# Get all global IP addresses and their subnets, filter out loopback and docker interfaces
SUBNETS=($(ip -o -f inet addr show | awk '/scope global/ {print $4}' | grep -v \'172.17\' | sort -u))

if [ ${#SUBNETS[@]} -eq 0 ]; then
    log_warning "No active subnets detected. If you want to advertise subnets, please ensure your network interfaces are configured correctly."
else
    log_info "You can advertise these subnets to your Tailscale network, making them accessible from other devices on your tailnet."
    log_info "See: https://tailscale.com/kb/1019/subnets"

    ROUTES_TO_ADVERTISE=()
    RECOMMENDED_SUBNET=""
    OTHER_SUBNETS=()

    # Find the recommended subnet
    for SUBNET in "${SUBNETS[@]}"; do
        if [[ $SUBNET == *\.100\.* ]]; then
            RECOMMENDED_SUBNET=$SUBNET
        else
            OTHER_SUBNETS+=($SUBNET)
        fi
    done

    if [ -n "$RECOMMENDED_SUBNET" ]; then
        read -p "📡 Recommended: Advertise dedicated Tailscale VLAN subnet $RECOMMENDED_SUBNET? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            ROUTES_TO_ADVERTISE+=($RECOMMENDED_SUBNET)
        fi

        read -p "Do you want to advertise any other subnets? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for SUBNET in "${OTHER_SUBNETS[@]}"; do
                read -p "📡 Advertise subnet $SUBNET? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    ROUTES_TO_ADVERTISE+=($SUBNET)
                fi
            done
        fi
    else
        for SUBNET in "${SUBNETS[@]}"; do
            read -p "📡 Advertise subnet $SUBNET? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ROUTES_TO_ADVERTISE+=($SUBNET)
            fi
        done
    fi

    if [ ${#ROUTES_TO_ADVERTISE[@]} -gt 0 ]; then
        TS_EXTRA_ARGS="--advertise-routes=$(IFS=,; echo "${ROUTES_TO_ADVERTISE[*]}")"
        log_success "Will advertise the following routes: $(IFS=,; echo "${ROUTES_TO_ADVERTISE[*]}")"
    fi
fi

# --- Exit Node ---
log_info "You can configure this Firewalla as an 'exit node'. This allows you to route all your internet traffic through your home network when you are away."
log_info "See: https://tailscale.com/kb/1019/subnets#exit-nodes"
read -p "🚪 Use this Firewalla as an exit node? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"
    log_success "Firewalla will be configured as an exit node."
fi

# --- Exit Node ---
log_info "You can configure this Firewalla as an \'exit node\'. This allows you to route all your internet traffic through your home network when you are away."
log_info "See: https://tailscale.com/kb/1019/subnets#exit-nodes"
read -p "🚪 Use this Firewalla as an exit node? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"
    log_success "Firewalla will be configured as an exit node."
fi

# --- DNS Settings ---
# Always accept DNS settings from the tailnet
TS_EXTRA_ARGS="$TS_EXTRA_ARGS --accept-dns=true"
log_info "DNS will be managed by Tailscale."

# --- Create docker-compose.yml ---

log_info "Creating docker-compose.yml file..."

if [ -f "$COMPOSE_FILE" ]; then
    read -p "⚠️  $COMPOSE_FILE already exists. Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Skipping creation of $COMPOSE_FILE."
        # If we skip creation, we should also skip the rest of the docker-compose related steps
        # but the script is not designed for that. So we just exit.
        exit 0
    fi
fi

COMPOSE_CONTENT=$(cat <<EOF
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: ts-firewalla
    environment:
      - TS_AUTHKEY=$TS_AUTHKEY
      - TS_EXTRA_ARGS=$TS_EXTRA_ARGS
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
    volumes:
      - $STATE_DIR:/var/lib/tailscale
      - $CONFIG_DIR:/config
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - sys_module
    network_mode: host
    restart: unless-stopped
EOF
)

if [ "$TEST_MODE" = true ]; then
    echo "DRY RUN: Would write the following to $COMPOSE_FILE:"
    echo "$COMPOSE_CONTENT"
elif [ "$CONFIRM_MODE" = true ]; then
    read -p "Write docker-compose.yml to $COMPOSE_FILE? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$COMPOSE_CONTENT" | sudo tee "$COMPOSE_FILE" > /dev/null
    else
        log_warning "Skipping creation of $COMPOSE_FILE."
    fi
else
    echo "$COMPOSE_CONTENT" | sudo tee "$COMPOSE_FILE" > /dev/null
fi

if [ $? -eq 0 ]; then
    log_success "docker-compose.yml handled successfully."
else
    log_error "Failed to handle docker-compose.yml. Exiting."
    exit 1
fi

# --- Pull Docker Image and Start Container ---

log_info "Pulling Tailscale Docker image and starting container..."
cd "$DOCKER_DIR" || { log_error "Failed to change directory to $DOCKER_DIR. Exiting."; exit 1; }
run_cmd sudo docker-compose pull || { log_error "Failed to pull Tailscale Docker image. Exiting."; exit 1; }
run_cmd sudo docker-compose up -d || { log_error "Failed to start Tailscale container. Exiting."; exit 1; }
log_success "Tailscale container started successfully!"

# --- Download Uninstall Script ---

log_info "Downloading uninstall script to $UNINSTALL_SCRIPT_PATH..."

if [ -f "$UNINSTALL_SCRIPT_PATH" ]; then
    read -p "⚠️  $UNINSTALL_SCRIPT_PATH already exists. Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Skipping download of uninstall script."
    else
        run_cmd sudo curl -sSL "$UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to download uninstall script."; }
        run_cmd sudo chmod +x "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to make uninstall script executable."; }
        log_success "Uninstall script downloaded and made executable."
    fi
else
    run_cmd sudo curl -sSL "$UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to download uninstall script."; }
    run_cmd sudo chmod +x "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to make uninstall script executable."; }
    log_success "Uninstall script downloaded and made executable."
fi

# --- Post-installation Instructions ---

log_info "🎉 Installation Complete! 🎉"
log_info "Next Steps:"
log_info "1. 🌐 Authorize your Firewalla device in the Tailscale admin console (https://login.tailscale.com/admin/machines)."
log_info "2. 🛣️ If you advertised subnet routes (--advertise-routes), enable them in the Tailscale admin console for your Firewalla device."
log_info "3. 🚪 If you advertised an exit node (--advertise-exit-node), enable it in the Tailscale admin console for your Firewalla device."
log_info "4. 🗑️ To uninstall, run: sudo $UNINSTALL_SCRIPT_PATH"
log_info "Enjoy your Tailscale-enabled Firewalla! 🚀"
