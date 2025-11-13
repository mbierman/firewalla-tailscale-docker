#!/bin/bash
# VERSION:1.3.0
set -e
set -o pipefail

# Emoji for user-facing output
INFO="ℹ️"
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
VERSION="1.3.0"

# --- Command-line flags ---
TEST_MODE=false
CONFIRM_MODE=false

while getopts "tc" opt; do
	case ${opt} in
		t) TEST_MODE=true ;;
		c) CONFIRM_MODE=true ;;
		*) echo "Invalid option: -${OPTARG}" >&2; exit 1 ;;
	esac
done
shift $((OPTIND -1))

# --- Paths ---
TAILSCALE_DIR="/home/pi/.firewalla/run/docker/tailscale"
DOCKER_COMPOSE_FILE="$TAILSCALE_DIR/docker-compose.yml"
TAILSCALE_DATA_DIR="/data/tailscale"
START_SCRIPT="/home/pi/.firewalla/config/post_main.d/tailscale-start.sh"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-tailscale.conf"
UNINSTALL_SCRIPT="/data/tailscale-uninstall.sh"

# --- Functions ---

# Function to execute or display commands
run_command() {
	if [ "$TEST_MODE" = true ]; then
		echo "[TEST MODE] Would run: $@"
	elif [ "$CONFIRM_MODE" = true ]; then
		read -p "Run this command? '$@' [y/N] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			"$@"
		else
			echo "Skipping command."
		fi
	else
		"$@"
	fi
}

# Function to determine and execute the correct docker compose command
docker_compose_command() {
	if docker compose version &>/dev/null; then
		run_command sudo docker compose "$@"
	elif docker-compose version &>/dev/null; then
		run_command sudo docker-compose "$@"
	else
		echo "$ERROR Neither 'docker compose' nor 'docker-compose' found. Please install Docker Compose."
		exit 1
	fi
}

echo "$INFO Starting Tailscale uninstallation (v$VERSION)..."

# 1. Stop and remove the Docker container
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
	echo "$INFO Stopping and removing Tailscale container..."
	docker_compose_command -f "$DOCKER_COMPOSE_FILE" down -v
	echo "$SUCCESS Tailscale container stopped and volumes removed."
else
	echo "$INFO docker-compose.yml not found. Skipping container removal."
fi

# 2. Remove configuration directory
if [ -d "$TAILSCALE_DIR" ]; then
	echo "$INFO Removing Tailscale configuration directory..."
	run_command sudo rm -rf "$TAILSCALE_DIR"
	echo "$SUCCESS Tailscale configuration directory removed."
fi

# 3. Remove Tailscale data directory
if [ -d "$TAILSCALE_DATA_DIR" ]; then
	echo "$INFO Removing Tailscale data directory..."
	run_command sudo rm -rf "$TAILSCALE_DATA_DIR"
	echo "$SUCCESS Tailscale data directory removed."
fi

# 4. Remove persistent IP forwarding
if [ -f "$SYSCTL_CONF_FILE" ]; then
	echo "$INFO Removing persistent IP forwarding config..."
	run_command sudo rm -f "$SYSCTL_CONF_FILE"
	# Reload sysctl to apply the change
	run_command sudo sysctl --system
	echo "$SUCCESS IP forwarding config removed."
fi

# 5. Remove the Tailscale start script
if [ -f "$START_SCRIPT" ]; then
	echo "$INFO Removing Tailscale start script..."
	run_command sudo rm -f "$START_SCRIPT"
	echo "$SUCCESS Tailscale start script removed."
fi

# 6. Remove the uninstall script itself
if [ -f "$UNINSTALL_SCRIPT" ]; then
	echo "$INFO Removing uninstall script..."
	run_command sudo rm -f "$UNINSTALL_SCRIPT"
	echo "$SUCCESS Uninstall script removed."
fi

echo ""
echo "$SUCCESS Tailscale uninstallation complete! 👋"
echo "$INFO You may want to manually remove the Firewalla device from your"
echo "$INFO Tailscale admin console if it's still listed."
echo ""
