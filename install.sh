#!/bin/bash
set -e
set -o pipefail

# Emoji for user-facing output
INFO="ℹ️ "
QUESTION="❔" 
SUCCESS="✅ "
WARNING="⚠️ "
ERROR="❌ "
VERSION="1.2.0 " 

# Function to check if a URL exists
check_url_exists() {
    local url="$1"
    if ! curl -s --head --fail "$url" > /dev/null; then
        echo "$ERROR The URL '$url' for the uninstall script was not found or is inaccessible. Please check the URL and your network connection."
        exit 1
    fi
}

# --- Paths ---
TAILSCALE_DIR="/home/pi/.firewalla/run/docker/tailscale"
DOCKER_COMPOSE_FILE="$TAILSCALE_DIR/docker-compose.yml"
TAILSCALE_DATA_DIR="/data/tailscale"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-tailscale.conf"
UNINSTALL_SCRIPT="/data/tailscale-uninstall.sh"
GITHUB_REPO="mbierman/tailscale-firewalla"
LATEST_UNINSTALL_SCRIPT_URL="https://gist.githubusercontent.com/mbierman/c5a0bbac7e9c7da4d6e74c329a3a953f/raw/a53738296f23fffa8fd839fb843d7fe9ce871f26/tailscale_uninstall.sh"
check_url_exists "$LATEST_UNINSTALL_SCRIPT_URL"

# --- Command-line flags ---
TEST_MODE=false
CONFIRM_MODE=false
DUMMY_MODE=false
# TS_EXTRA_ARGS="-accept-dns=true " # Initialize TS_EXTRA_ARGS
TS_EXTRA_ARGS="" # Initialize TS_EXTRA_ARGS

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

# Function to convert subnet from Firewalla format (e.g., 192.168.0.1/24) to Tailscale format (e.g., 192.168.0.0/24)
convert_subnet_to_tailscale_format() {
	local subnet="$1"
	# Extract the IP address and CIDR
	local ip_address=$(echo "$subnet" | cut -d'/' -f1)
	local cidr=$(echo "$subnet" | cut -d'/' -f2)

	# Replace the last octet of the IP address with 0
	local network_address=$(echo "$ip_address" | awk -F'.' '{print $1"."$2"."$3".0"}')

	echo "${network_address}/${cidr}"
}

# Function to get available subnets from bridge interfaces
get_available_subnets() {
	ip -o -f inet addr show | grep -E ': br[0-9]+' | awk '{print $4}'
}

# Function to generate docker-compose.yml content
generate_docker_compose_yml() {
	local hostname="$1"
	local authkey="$2"
	local advertised_routes="$3"
	local extra_args="$4"
	local data_dir="$5"

	cat <<-EOF
	version: '3.8'
	services:
	  tailscale:
	    container_name: tailscale
	    image: tailscale/tailscale:latest
	    hostname: ${hostname}
	    volumes:
	      - "${data_dir}:/var/lib/tailscale"
	      - "/dev/net/tun:/dev/net/tun"
	    cap_add:
	      - NET_ADMIN
	      - SYS_MODULE
	    environment:
           - TS_ACCEPT_DNS=true
           - TS_USERSPACE=false
           - TS_ROUTES=${advertised_routes}
           - TS_AUTHKEY=${authkey}
           - TS_STATE_DIR=/var/lib/tailscale
           - TS_ACCEPT_ROUTES=true
           - TS_EXTRA_ARGS=--accept-routes ${TS_EXTRA_ARGS} 
	    network_mode: host
	    restart: unless-stopped
	EOF
}
          # REMOVE
          # - TS_ADVERTISE_ROUTES=${advertised_routes}
          # - TS_EXTRA_ARGS=--advertise-routes=192.168.1.0/24 --advertise-exit-node --accept-dns=true
	     # - TS_EXTRA_ARGS=--accept-routes ${TS_EXTRA_ARGS} --advertise-routes=${advertised_routes}

# --- Script Start ---

echo "$INFO Starting Tailscale installation for Firewalla (v$VERSION)..."

# 1. Enable IP Forwarding
echo "$INFO Enabling persistent IP forwarding..."
if [ ! -f "$SYSCTL_CONF_FILE" ] && { [ "$TEST_MODE" = true ] || [ "$CONFIRM_MODE" = true ]; }; then
     run_command echo "net.ipv4.ip_forward=1"
     run_command echo "net.ipv6.conf.all.forwarding=1"
elif [ ! -f "$SYSCTL_CONF_FILE" ] && { [ "$TEST_MODE" = false ] && [ "$CONFIRM_MODE" = false ]; }; then
    run_command echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a "$SYSCTL_CONF_FILE" > /dev/null
     run_command echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a "$SYSCTL_CONF_FILE" > /dev/null
elif [ -f "$SYSCTL_CONF_FILE" ]; then
    echo "$INFO IP forwarding configuration already exists."
fi


# 2. Install/Update Uninstall Script
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

# 3. Create Directories
echo "$INFO Creating directories..."
run_command sudo mkdir -p "$TAILSCALE_DIR" "$TAILSCALE_DATA_DIR"
sudo chown pi:pi "$TAILSCALE_DIR" "$TAILSCALE_DATA_DIR"
echo "$SUCCESS Directories created."

# 4. Gather User Input
if [ "$DUMMY_MODE" = true ]; then
	# Dummy data for -d flag
	echo "[DEV MODE] Skipping user input and using dummy data."
	TS_HOSTNAME="ts-firewalla-test"
	TS_AUTHKEY="tskey-test-key"
	TS_EXTRA_ARGS=""
	ADVERTISED_ROUTES="192.168.0.0/24"
else
	# Hostname
	read -p "$QUESTION Enter a hostname for this Tailscale node [ts-firewalla]: " TS_HOSTNAME
	TS_HOSTNAME=${TS_HOSTNAME:-ts-firewalla}

	#  Tailscale Auth Key
	while true; do
		read -p "$QUESTION Enter your Tailscale Auth Key (must start with 'tskey-'): " TS_AUTHKEY
		if [[ "$TS_AUTHKEY" == tskey-* ]]; then
			break
		else
			echo "$ERROR Invalid format. The Auth Key must start with 'tskey-'."
		fi
	done

	# Exit Node
	read -p "$QUESTION Do you want to use this device as a Tailscale exit node? (y/N): " USE_EXIT_NODE
	if [[ "$USE_EXIT_NODE" =~ ^[Yy]$ ]]; then
		TS_EXTRA_ARGS="--exit-node --exit-node-allow-lan-access"
		echo "$QUESTION This device will be configured as an exit node."
	else
		TS_EXTRA_ARGS=""
		echo "$INFO This device will not be configured as an exit node."
	fi
         #  TS_EXTRA_ARGS="-accept-dns=true ${TS_EXTRA_ARGS}"    
fi

# 5. Discover and set subnets
echo "$INFO Discovering available subnets..."
if [ "$DUMMY_MODE" = false ]; then
    # Read subnets line by line into an array
    readarray -t AVAILABLE_SUBNETS < <(get_available_subnets)

    if [ "${#AVAILABLE_SUBNETS[@]}" -eq 0 ]; then
        echo "$WARNING No bridge interfaces with subnets found. Subnet routing will be disabled."
        ADVERTISED_ROUTES=""
    else
        ADVERTISED_ROUTES=""
        for subnet in "${AVAILABLE_SUBNETS[@]}"; do
            # Trim whitespace just in case
            subnet=$(echo "$subnet" | xargs)
            tailscale_subnet=$(convert_subnet_to_tailscale_format "$subnet")

            # Default to N if non-interactive
            if [ -t 0 ]; then
                read -p "$QUESTION Do you want to advertise the subnet $tailscale_subnet? (y/N): " ADVERTISE_SUBNET
            else
                ADVERTISE_SUBNET="N"
            fi

            if [[ "$ADVERTISE_SUBNET" =~ ^[Yy]$ ]]; then
                if [ -z "$ADVERTISED_ROUTES" ]; then
                    ADVERTISED_ROUTES="$tailscale_subnet"
                else
                    ADVERTISED_ROUTES="$ADVERTISED_ROUTES,$tailscale_subnet"
                fi
                echo "$SUCCESS Subnet $tailscale_subnet will be advertised."
            else
                echo "$INFO Subnet $tailscale_subnet will NOT be advertised."
            fi
        done

        if [ -z "$ADVERTISED_ROUTES" ]; then
            echo "$WARNING No subnets selected for advertisement."
        else
            echo "$SUCCESS Will advertise the following subnets: $ADVERTISED_ROUTES"
        fi
    fi
fi

# 6. Create docker-compose.yml
echo "$INFO Creating docker-compose.yml file..."
if [ "$DUMMY_MODE" = true ]; then
	echo "[DEV MODE] Would create $DOCKER_COMPOSE_FILE with the following content:"
	generate_docker_compose_yml "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXTRA_ARGS}" "${TAILSCALE_DATA_DIR}"
elif [ "$TEST_MODE" = true ]; then
	echo "[TEST MODE] Would create $DOCKER_COMPOSE_FILE with the following content:"
	generate_docker_compose_yml "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXTRA_ARGS}" "${TAILSCALE_DATA_DIR}"
elif [ "$CONFIRM_MODE" = true ]; then
	COMPOSE_CONTENT=$(generate_docker_compose_yml "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXTRA_ARGS}" "${TAILSCALE_DATA_DIR}")
	echo "The following docker-compose.yml will be created:"
	echo "${COMPOSE_CONTENT}"
	read -p "Create this file? [y/N] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "${COMPOSE_CONTENT}" | sudo tee "$DOCKER_COMPOSE_FILE" > /dev/null
		echo "$SUCCESS docker-compose.yml created."
	else
		echo "Skipping docker-compose.yml creation."
	fi
else
	generate_docker_compose_yml "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXTRA_ARGS}" "${TAILSCALE_DATA_DIR}" | sudo tee "$DOCKER_COMPOSE_FILE" > /dev/null
	echo "$SUCCESS docker-compose.yml created."
fi


# 7. Start the container
echo "$INFO Pulling the latest Tailscale image..."
docker_compose_command -f "$DOCKER_COMPOSE_FILE" pull
echo "$INFO Starting the Tailscale container..."
docker_compose_command -f "$DOCKER_COMPOSE_FILE" up -d

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
echo "
