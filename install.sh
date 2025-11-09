#!/bin/bash
set -e
set -o pipefail

# Emoji for user-facing output
INFO="ℹ️"
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
VERSION="1.2.0" 

# --- Paths ---
TAILSCALE_DIR="/home/pi/.firewalla/run/docker/tailscale"
DOCKER_COMPOSE_FILE="$TAILSCALE_DIR/docker-compose.yml"
TAILSCALE_DATA_DIR="/data/tailscale"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-tailscale.conf"
UNINSTALL_SCRIPT="/data/tailscale-uninstall.sh"
GITHUB_REPO="mbierman/tailscale-firewalla"
LATEST_UNINSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/refs/heads/main/uninstall.sh?token=GHSAT0AAAAAADNA3IRKXOWYMN5OUT2R3LXM2IRET2A"

# --- Command-line flags ---
TEST_MODE=false
CONFIRM_MODE=false
DUMMY_MODE=false

while getopts "tcd" opt; do
	case ${opt} in
		t) TEST_MODE=true ;;
		c) CONFIRM_MODE=true ;;
		d) DUMMY_MODE=true ;;
		*) echo "Invalid option: -${OPTARG}" >&2; exit 1 ;;
	esac
done
shift $((OPTIND -1))

# --- Functions ---

# Check for mutually exclusive flags
if [ "$TEST_MODE" = true ] && [ "$DUMMY_MODE" = true ]; then
	echo "$ERROR The -t (test) and -d (dummy) flags are mutually exclusive. Please use one or the other."
	exit 1
fi

# Function to execute or display commands
run_command() {
	if [ "$DUMMY_MODE" = true ]; then
		echo "[DEV MODE] Would run: $@"
	elif [ "$TEST_MODE" = true ]; then
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

# Function to get available subnets from bridge interfaces
get_available_subnets() {
	ip -o -f inet addr show | grep -E ': br[0-9]+' | awk '{print $4}'
}

# --- Script Start ---

echo "$INFO Starting Tailscale installation for Firewalla (v$VERSION)..."
# 1. Install/Update Uninstall Script
echo "$INFO Checking for uninstall script..."
LOCAL_VERSION=""

# Get local version if available
if [ -f "$UNINSTALL_SCRIPT" ]; then
	# Source the script in a subshell to avoid variable conflicts
	LOCAL_VERSION=$( (source "$UNINSTALL_SCRIPT" && echo "$VERSION") )
fi

# Get remote version
REMOTE_VERSION=$(curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" | head -n 2 | grep -m 1 'VERSION:' | cut -d':' -f2) 

if [ -z "$REMOTE_VERSION" ]; then
	echo "$WARNING Could not fetch remote uninstall script version. Will download unconditionally."
	run_command sudo curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT"
	run_command sudo chmod +x "$UNINSTALL_SCRIPT"
elif [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
echo hello
	echo "$INFO New uninstall script version ($REMOTE_VERSION) found. Updating..."
	run_command sudo curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT"
	run_command sudo chmod +x "$UNINSTALL_SCRIPT"
	echo "$SUCCESS Uninstall script updated to version $REMOTE_VERSION."
else
	echo "$SUCCESS Uninstall script is already up to date (v$LOCAL_VERSION)."
fi

# 2. Create Directories
echo "$INFO Creating directories..."
run_command sudo mkdir -p "$TAILSCALE_DIR" "$TAILSCALE_DATA_DIR"
echo "$SUCCESS Directories created."

# 3. Gather User Input
if [ "$DUMMY_MODE" = true ]; then
	# Dummy data for -d flag
	echo "[DEV MODE] Skipping user input and using dummy data."
	TS_HOSTNAME="ts-firewalla-test"
	TS_AUTHKEY="tskey-test-key"
	TS_EXTRA_ARGS=""
	ADVERTISED_ROUTES="192.168.0.0/24"
else
	# Hostname
	read -p "$INFO Enter a hostname for this Tailscale node [ts-firewalla]: " TS_HOSTNAME
	TS_HOSTNAME=${TS_HOSTNAME:-ts-firewalla}

	#  Tailscale Auth Key
	while true; do
		read -p "$INFO Enter your Tailscale Auth Key (must start with 'tskey-'): " TS_AUTHKEY
		if [[ "$TS_AUTHKEY" == tskey-* ]]; then
			break
		else
			echo "$ERROR Invalid format. The Auth Key must start with 'tskey-'."
		fi
	done

	# Exit Node
	read -p "$INFO Do you want to use this device as a Tailscale exit node? (y/N): " USE_EXIT_NODE
	if [[ "$USE_EXIT_NODE" =~ ^[Yy]$ ]]; then
		TS_EXTRA_ARGS="--exit-node --exit-node-allow-lan-access"
		echo "$INFO This device will be configured as an exit node."
	else
		TS_EXTRA_ARGS=""
		echo "$INFO This device will not be configured as an exit node."
	fi
fi

# 4. Discover and set subnets
echo "$INFO Discovering available subnets..."
if [ "$DUMMY_MODE" = false ]; then
	AVAILABLE_SUBNETS=($(get_available_subnets))
	if [ ${#AVAILABLE_SUBNETS[@]} -eq 0 ]; then
		echo "$WARNING No bridge interfaces with subnets found. Subnet routing will be disabled."
		ADVERTISED_ROUTES=""
	else
          # NO user should be asked if they want to use each subnet. 
		ADVERTISED_ROUTES=$(IFS=,; echo "${AVAILABLE_SUBNETS[*]}")
		echo "$SUCCESS Found and will advertise the following subnets: $ADVERTISED_ROUTES"
	fi
fi

# 5. Create docker-compose.yml
echo "$INFO Creating docker-compose.yml file..."
if [ "$DUMMY_MODE" = true ]; then
	echo "[DEV MODE] Would create $DOCKER_COMPOSE_FILE with dummy values."
elif [ "$CONFIRM_MODE" = true ]; then
	echo "The following docker-compose.yml will be created:"
	cat <<-EOF
	version: '3.8'
	services:
	  tailscale:
	    container_name: tailscale
	    image: tailscale/tailscale:latest
	    hostname: ${TS_HOSTNAME}
	    volumes:
	      - "${TAILSCALE_DATA_DIR}:/var/lib/tailscale"
	      - "/dev/net/tun:/dev/net/tun"
	    cap_add:
	      - NET_ADMIN
	      - SYS_MODULE
	    environment:
	      - TS_AUTHKEY=${TS_AUTHKEY}
	      - TS_STATE_DIR=/var/lib/tailscale
	      - TS_ACCEPT_ROUTES=true
	      - TS_ADVERTISE_ROUTES=${ADVERTISED_ROUTES}
	      - TS_EXTRA_ARGS=${TS_EXTRA_ARGS}
	    network_mode: host
	    restart: unless-stopped
	EOF
	read -p "Create this file? [y/N] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		sudo tee "$DOCKER_COMPOSE_FILE" > /dev/null <<-EOF
		version: '3.8'
		services:
		  tailscale:
		    container_name: tailscale
		    image: tailscale/tailscale:latest
		    hostname: ${TS_HOSTNAME}
		    volumes:
		      - "${TAILSCALE_DATA_DIR}:/var/lib/tailscale"
		      - "/dev/net/tun:/dev/net/tun"
		    cap_add:
		      - NET_ADMIN
		      - SYS_MODULE
		    environment:
		      - TS_AUTHKEY=${TS_AUTHKEY}
		      - TS_STATE_DIR=/var/lib/tailscale
		      - TS_ACCEPT_ROUTES=true
		      - TS_ADVERTISE_ROUTES=${ADVERTISED_ROUTES}
		      - TS_EXTRA_ARGS=${TS_EXTRA_ARGS}
		    network_mode: host
		    restart: unless-stopped
		EOF
		echo "$SUCCESS docker-compose.yml created."
	else
		echo "Skipping docker-compose.yml creation."
	fi
else
	sudo tee "$DOCKER_COMPOSE_FILE" > /dev/null <<-EOF
	version: '3.8'
	services:
	  tailscale:
	    container_name: tailscale
	    image: tailscale/tailscale:latest
	    hostname: ${TS_HOSTNAME}
	    volumes:
	      - "${TAILSCALE_DATA_DIR}:/var/lib/tailscale"
	      - "/dev/net/tun:/dev/net/tun"
	    cap_add:
	      - NET_ADMIN
	      - SYS_MODULE
	    environment:
	      - TS_AUTHKEY=${TS_AUTHKEY}
	      - TS_STATE_DIR=/var/lib/tailscale
	      - TS_ACCEPT_ROUTES=true
	      - TS_ADVERTISE_ROUTES=${ADVERTISED_ROUTES}
	      - TS_EXTRA_ARGS=${TS_EXTRA_ARGS}
	    network_mode: host
	    restart: unless-stopped
	EOF
	echo "$SUCCESS docker-compose.yml created."
fi

# 6. Enable IP Forwarding
echo "$INFO Enabling persistent IP forwarding..."
if [ ! -f "$SYSCTL_CONF_FILE" ] || [ "$TEST_MODE" = true ] || [ "$CONFIRM_MODE" = true ]; then
	run_command echo "net.ipv4.ip_forward=1" | sudo tee "$SYSCTL_CONF_FILE" > /dev/null
	run_command echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a "$SYSCTL_CONF_FILE" > /dev/null
	run_command sudo sysctl -p "$SYSCTL_CONF_FILE"
	echo "$SUCCESS IP forwarding enabled and made persistent."
else
	echo "$INFO IP forwarding configuration already exists."
fi

# 7. Start the container
echo "$INFO Pulling the latest Tailscale image..."
run_command sudo docker compose -f "$DOCKER_COMPOSE_FILE" pull
echo "$INFO Starting the Tailscale container..."
run_command sudo docker compose -f "$DOCKER_COMPOSE_FILE" up -d

# 8. Verify Container Status
if [ "$TEST_MODE" = false ] && [ "$CONFIRM_MODE" = false ] && [ "$DUMMY_MODE" = false ]; then
	echo "$INFO Verifying container status..."
	for i in {1..5}; do
		STATUS=$(sudo docker inspect --format '{{.State.Status}}' tailscale)
		if [ "$STATUS" == "running" ]; then
			echo "$SUCCESS Tailscale container is running."
			break
		fi
		echo "$WARNING Container status is '$STATUS'. Waiting... (Attempt $i/5)"
		sleep 5
	done

	if [ "$STATUS" != "running" ]; then
		echo "$ERROR Tailscale container failed to start. Current status: '$STATUS'."
		echo "$INFO Please check the container logs for errors:"
		echo "    sudo docker logs tailscale"
		echo "$INFO Also, review your docker-compose.yml at $DOCKER_COMPOSE_FILE."
		exit 1
	fi
fi

# 9. Final Instructions
echo ""
echo "$SUCCESS Tailscale installation is complete! 🎉"
echo ""
echo "$INFO The Tailscale node on your Firewalla has been pre-authenticated with the key you provided."
echo "$INFO It should appear in your Tailscale admin console shortly."
echo ""
echo "$WARNING IMPORTANT: Authorize Subnet Routes"
echo "1. Go to your Tailscale Admin Console: https://login.tailscale.com/admin/machines"
echo "2. Find the '${TS_HOSTNAME}' device."
echo "3. Click the '...' menu and select 'Edit route settings...'."
echo "4. Approve the subnet route(s) for '${ADVERTISED_ROUTES}' to access your local network."
echo ""
echo "$INFO You can run the uninstaller later with: sudo $UNINSTALL_SCRIPT"
echo ""
