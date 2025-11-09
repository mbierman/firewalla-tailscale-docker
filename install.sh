#!/bin/bash

version="1.0.0"
# Credit to u/adrianmihalko for the original docker-compose concept
# https://www.reddit.com/r/firewalla/comments/1mlrtvi/easy_tailscale_integration_via_docker_compose/

# 🚀 Tailscale Docker Installer for Firewalla 🚀

# --- Configuration ---
DOCKER_DIR="/data/tailscale"
COMPOSE_DIR="/home/pi/.firewalla/run/docker/tailscale"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
STATE_DIR="$DOCKER_DIR/ts-firewalla/state"
CONFIG_DIR="$DOCKER_DIR/ts-firewalla/config"
UNINSTALL_SCRIPT_PATH="/data/uninstall-tailscale-firewalla.sh"
STARTUP_SCRIPT_PATH="/home/pi/.firewalla/config/post_main.d/start_tailscale.sh"
IP_FORWARD_CONF_FILE="/etc/sysctl.d/99-tailscale-forwarding.conf"
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
        # Only prompt if running in an interactive terminal
        if [ -t 0 ]; then
            read -p "Execute '$*'? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_warning "Skipping command."
                return 1 # Indicate skipped
            fi
        else
            log_warning "Running in non-interactive mode. Assuming 'yes' for all confirmations."
        fi
    fi

    "$@"
}

# --- Pre-checks ---

log_info "Starting Tailscale Docker installation for Firewalla..."

# --- Create Directories ---

log_info "Creating necessary directories..."
run_cmd sudo mkdir -p "$STATE_DIR" "$CONFIG_DIR" "$COMPOSE_DIR" || { log_error "Failed to create directories."; exit 1; }
log_success "Directories created: $STATE_DIR, $CONFIG_DIR, and $COMPOSE_DIR"

# --- Get User Input ---

log_info "Please provide the following information for Tailscale configuration:"

log_info "You can generate a reusable Auth Key from your Tailscale admin console."
log_info "See: https://tailscale.com/kb/1085/auth-keys/"

while true; do
    read -p "🔑 Enter your Tailscale Auth Key (e.g., tskey-auth-xxxxxxxxxxxxx): " TS_AUTHKEY
    if [ -z "$TS_AUTHKEY" ]; then
        log_error "Tailscale Auth Key cannot be empty. Please try again."
    elif [[ "$TS_AUTHKEY" == tskey-auth-* ]]; then
        break
    else
        log_error "Invalid Tailscale Auth Key format. It must start with 'tskey-auth-'. Please try again."
    fi
done

TS_EXTRA_ARGS=""

log_info "Before proceeding, please open your Firewalla app and go to Network Manager to identify the names of your networks (LAN, Guest, IoT, etc.) and their corresponding subnets. This will help you decide which subnets to advertise."

# --- Advertise Subnets ---
log_info "Detecting local subnets..."

SUBNETS=($(ip -o -f inet addr show | grep -e ': br[0-9]*' | awk '{print $4}' | sort -u))

if [ ${#SUBNETS[@]} -eq 0 ]; then
    log_warning "No active subnets detected. If you want to advertise subnets, please ensure your network interfaces are configured correctly."
else
    log_info "You can advertise these subnets to your Tailscale network, making them accessible from other devices on your tailnet."
    log_info "See: https://tailscale.com/kb/1019/subnets"

    ROUTES_TO_ADVERTISE=()

    for SUBNET in "${SUBNETS[@]}"; do
        read -p "📡 Advertise subnet $SUBNET? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ROUTES_TO_ADVERTISE+=($SUBNET)
        fi
    done

    if [ ${#ROUTES_TO_ADVERTISE[@]} -gt 0 ]; then
        TS_EXTRA_ARGS="--advertise-routes=$(IFS=,; echo "${ROUTES_TO_ADVERTISE[*]}")"
        log_success "Will advertise the following routes: $(IFS=,; echo "${ROUTES_TO_ADVERTISE[*]}")"
    fi
fi

# --- Exit Node ---
log_info "You can configure this Firewalla as an 'exit node'. This allows you to route all your internet traffic through your home network when you are away."
log_info "See: https://tailscale.com/kb/1019/subnets#exit-nodes"
read -p "🚪 Do you want to enable the exit node feature? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"
    log_success "Firewalla will be configured as an exit node."
fi

# --- DNS Settings ---
# Always accept DNS settings from the tailnet
TS_EXTRA_ARGS="$TS_EXTRA_ARGS --accept-dns=true"
log_info "DNS will be managed by Tailscale."

# --- Create Startup Script ---

log_info "Creating startup script..."

create_startup_script() {
    local script_content
    script_content=$(cat <<EOF
#!/bin/bash

# Ensure IP forwarding is enabled and persistent via /etc/sysctl.d/
# This script checks for the sysctl.d file and recreates it if necessary.
IP_FORWARD_CONF_FILE="/etc/sysctl.d/99-tailscale-forwarding.conf"
REQUIRED_V4="net.ipv4.ip_forward = 1"
REQUIRED_V6="net.ipv6.conf.all.forwarding = 1"

if [ ! -f "\$IP_FORWARD_CONF_FILE" ] || ! grep -q "\$REQUIRED_V4" "\$IP_FORWARD_CONF_FILE" || ! grep -q "\$REQUIRED_V6" "\$IP_FORWARD_CONF_FILE"; then
    echo "⚠️  IP forwarding configuration file missing or incorrect. Recreating..."
    local sysctl_conf_content="\$REQUIRED_V4
\$REQUIRED_V6"
    echo "\$sysctl_conf_content" | sudo tee "\$IP_FORWARD_CONF_FILE" > /dev/null
    sudo sysctl -p "\$IP_FORWARD_CONF_FILE"
    echo "✅ IP forwarding configuration ensured."
else
    # Ensure settings are loaded, in case they were manually unloaded
    if ! sysctl -n net.ipv4.ip_forward | grep -q "1" || ! sysctl -n net.ipv6.conf.all.forwarding | grep -q "1"; then
        echo "ℹ️  IP forwarding settings not active. Loading from \$IP_FORWARD_CONF_FILE..."
        sudo sysctl -p "\$IP_FORWARD_CONF_FILE"
        echo "✅ IP forwarding settings loaded."
    fi
fi

# Start Tailscale container
cd "$COMPOSE_DIR" || exit
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    docker compose up -d
fi
EOF
)

    run_cmd echo "$script_content" | sudo tee "$STARTUP_SCRIPT_PATH" > /dev/null
    if [ $? -eq 0 ]; then
        run_cmd sudo chmod +x "$STARTUP_SCRIPT_PATH"
        log_success "Startup script created successfully at $STARTUP_SCRIPT_PATH."
    else
        log_error "Failed to create startup script. Exiting."
        exit 1
    fi
}

enable_ip_forwarding_now() {
    log_info "Enabling IP forwarding for the current session..."
    run_cmd sudo sysctl -w net.ipv4.ip_forward=1 || { log_error "Failed to set net.ipv4.ip_forward."; exit 1; }
    run_cmd sudo sysctl -w net.ipv6.conf.all.forwarding=1 || { log_error "Failed to set net.ipv6.conf.all.forwarding."; exit 1; }
    log_success "IP forwarding enabled."
}

make_ip_forwarding_persistent_sysctld() {
    log_info "Creating persistent IP forwarding configuration in /etc/sysctl.d/..."
    local sysctl_conf_content="net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1"
    run_cmd echo "$sysctl_conf_content" | sudo tee "$IP_FORWARD_CONF_FILE" > /dev/null || { log_error "Failed to create $IP_FORWARD_CONF_FILE."; exit 1; }
    run_cmd sudo sysctl -p "$IP_FORWARD_CONF_FILE" || { log_error "Failed to load settings from $IP_FORWARD_CONF_FILE."; exit 1; }
    log_success "Persistent IP forwarding configured via $IP_FORWARD_CONF_FILE."
}

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

run_cmd echo "$COMPOSE_CONTENT" | sudo tee "$COMPOSE_FILE" > /dev/null

if [ $? -eq 0 ]; then
    log_success "docker-compose.yml handled successfully."
else
    log_error "Failed to handle docker-compose.yml. Exiting."
    exit 1
fi

# --- Enable IP Forwarding and Start Container ---

log_info "Enabling IP forwarding and starting container..."
enable_ip_forwarding_now
make_ip_forwarding_persistent_sysctld

cd "$COMPOSE_DIR" || { log_error "Failed to change directory to $COMPOSE_DIR. Exiting."; exit 1; }

log_info "Pulling latest Tailscale image..."
if command -v docker-compose &> /dev/null; then
    run_cmd sudo docker-compose pull || { log_error "Failed to pull Tailscale Docker image. Exiting."; exit 1; }
    log_info "Starting Tailscale container..."
    run_cmd sudo docker-compose up -d || { log_error "Failed to start Tailscale container. Exiting."; exit 1; }
else
    run_cmd sudo docker compose pull || { log_error "Failed to pull Tailscale Docker image. Exiting."; exit 1; }
    log_info "Starting Tailscale container..."
    run_cmd sudo docker compose up -d || { log_error "Failed to start Tailscale container. Exiting."; exit 1; }
fi

log_success "Tailscale container started successfully!"

# --- Download Uninstall Script ---

log_info "Downloading uninstall script to $UNINSTALL_SCRIPT_PATH..."

if [ -f "$UNINSTALL_SCRIPT_PATH" ]; then
    read -p "⚠️  $UNINSTALL_SCRIPT_PATH already exists. Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Skipping download of uninstall script."
    else
        run_cmd sudo curl -sSL "$UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT_PATH" && \
        run_cmd sudo chmod +x "$UNINSTALL_SCRIPT_PATH" || { log_error "Failed to download or make uninstall script executable."; }
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
