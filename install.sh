#!/bin/bash
set -e
set -o pipefail

# Emoji for user-facing output
INFO="ℹ️ "
QUESTION="❔" 
SUCCESS="✅ "
WARNING="⚠️ "
ERROR="❌ "
VERSION="1.3.0 " 

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
INTERFACES_FILE="/data/tailscale_interfaces"
START_SCRIPT="/home/pi/.firewalla/config/post_main.d/tailscale-start.sh"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-tailscale.conf"
UNINSTALL_SCRIPT="/data/tailscale-uninstall.sh"
GITHUB_REPO="mbierman/tailscale-firewalla"
LATEST_UNINSTALL_SCRIPT_URL="https://gist.githubusercontent.com/mbierman/c5a0bbac7e9c7da4d6e74c329a3a953f/raw/a53738296f23fffa8fd839fb843d7fe9ce871f26/tailscale_uninstall.sh"
check_url_exists "$LATEST_UNINSTALL_SCRIPT_URL"

# --- Command-line flags ---
TEST_MODE=false    # Test, but doesn't do anything
CONFIRM_MODE=false # Ask before doing 
DUMMY_MODE=false
TS_EXIT_NODE_FLAG=""   # Initialize TS_EXIT_NODE_FLAG

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
	ip -o -f inet addr show | grep -E ': br[0-9]+' | awk '{print $2, $4}' | sort -k 2 -V
}

# Function to generate docker-compose.yml
generate_docker_compose_yml() {
cat <<-EOF
version: "3.9"
services:
  tailscale:
    container_name: tailscale
    image: tailscale/tailscale:latest
    network_mode: host
    privileged: true
    restart: unless-stopped
    volumes:
      - ${TAILSCALE_DATA_DIR}:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    command: tailscaled --tun=userspace-networking
EOF

}

# Function to generate tailscale-start.sh content
generate_tailscale_start () {
# Ensure variables are local and correctly set from function arguments
	local hostname="$1"
    local authkey="$2"
    local advertised_routes="$3"
	local exit_node_flag="$4"
	local data_dir="$5"
	local DOCKER_COMPOSE_FILE="$6"
	local TEST_MODE="$7"
	local CONFIRM_MODE="$8"
	local DUMMY_MODE="$9"
	local INTERFACES_FILE="${10}"

# The script content generated below uses the local variables above
cat <<-EOF
#!/bin/bash
set -e

TEST_MODE=${TEST_MODE}
CONFIRM_MODE=${CONFIRM_MODE}
DUMMY_MODE=${DUMMY_MODE}

# Function to execute or display commands
run_command() {
	if [ "\$DUMMY_MODE" = true ]; then
		echo "[DEV MODE] Would run: \$@"
	elif [ "\$TEST_MODE" = true ]; then
		echo "[TEST MODE] Would run: \$@"
	elif [ "\$CONFIRM_MODE" = true ]; then
		read -p "Run this command? '\$@' [y/N] " -n 1 -r
		echo
		if [[ \$REPLY =~ ^[Yy]$ ]]; then
			"\$@"
		else
			echo "Skipping command."
		fi
	else
		"\$@"
	fi
}

# Function to determine and execute the correct docker compose command
docker_compose_command() {
	if docker compose version &>/dev/null; then
		run_command sudo docker compose "\$@"
	elif docker-compose version &>/dev/null; then
		run_command sudo docker-compose "\$@"
	else
		echo "Neither 'docker compose' nor 'docker-compose' found. Please install Docker Compose."
		exit 1
	fi
}

# Read selected interfaces from file
if [ -f "${INTERFACES_FILE}" ]; then
    selected_interfaces=$(grep -v '^#' "${INTERFACES_FILE}")
else
    selected_interfaces=""
fi

# Start the container (First run)
docker_compose_command -f $DOCKER_COMPOSE_FILE up -d 

# Add NAT rule(s)
for iface in \$selected_interfaces; do
	if ! sudo iptables -t nat -C POSTROUTING -s 100.64.0.0/10 -o "\$iface" -j MASQUERADE 2>/dev/null; then
		echo "Creating iptable NAT rule for \$iface..."
		run_command sudo iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -o "\$iface" -j MASQUERADE
	else
		echo "IP table NAT rule for \$iface already in place."
	fi
done

# Re-run docker-compose up -d
docker_compose_command -f $DOCKER_COMPOSE_FILE up -d 

# Loop until the container is running
echo "Waiting for the container to start..."
while ! sudo docker ps -q -f name=tailscale | grep -q .; do
    sleep 5
done
echo "Container started."

# Wait a few seconds for tailscaled to initialize
sleep 3

# Bring Tailscale online with your auth key and configuration
run_command sudo docker exec tailscale tailscale up \\
	--authkey="${authkey}" \\
	--hostname="${hostname}" \\
	--advertise-routes="${advertised_routes}" \\
	${exit_node_flag} \\
	--accept-routes \\
	--accept-dns \\
	--reset
EOF
}

# --- Script Start ---

echo "$INFO Starting Tailscale installation for Firewalla (v$VERSION)..."

# --- Section 1: IP Forwarding ---
echo "$INFO Enabling persistent IP forwarding..."
if [ ! -f "$SYSCTL_CONF_FILE" ]; then
	if [ "$TEST_MODE" = true ] || [ "$CONFIRM_MODE" = true ]; then
		run_command echo "net.ipv4.ip_forward=1"
		# run_command echo "net.ipv6.conf.all.forwarding=1"
	else
		sudo mkdir -p "$(dirname "$SYSCTL_CONF_FILE")"
		sudo bash -c "echo 'net.ipv4.ip_forward=1' >> '$SYSCTL_CONF_FILE'"
		sudo bash -c "echo 'net.ipv6.conf.all.forwarding=1' >> '$SYSCTL_CONF_FILE'"
		sudo sysctl --system
		echo "$SUCCESS IP forwarding enabled and applied."
	fi
else
	echo "$INFO IP forwarding configuration already exists."
fi

# --- Section 2: Uninstall Script ---
echo "$INFO Checking for uninstall script..."
LOCAL_VERSION=""
if [ -f "$UNINSTALL_SCRIPT" ]; then
	LOCAL_VERSION=$( (source "$UNINSTALL_SCRIPT" && echo "$VERSION") )
fi
REMOTE_VERSION=$(curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" | head -n 2 | grep -m 1 'VERSION:' | cut -d':' -f2)
if [ -z "$REMOTE_VERSION" ]; then
	echo "$WARNING Could not fetch remote uninstall script version. Will download unconditionally."
	run_command sudo curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT"
	run_command sudo chmod +x "$UNINSTALL_SCRIPT"
	run_command sudo chown pi:pi "$UNINSTALL_SCRIPT"
elif [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
	echo "$INFO New uninstall script version ($REMOTE_VERSION) found. Updating..."
	run_command sudo curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" -o "$UNINSTALL_SCRIPT"
	run_command sudo chmod +x "$UNINSTALL_SCRIPT"
	run_command sudo chown pi:pi "$UNINSTALL_SCRIPT"
	echo "$SUCCESS Uninstall script updated to version $REMOTE_VERSION."
else
	echo "$SUCCESS Uninstall script is already up to date (v$LOCAL_VERSION)."
fi

# --- Section 3: Directories ---
echo "$INFO Creating directories..."
run_command sudo mkdir -p "$TAILSCALE_DIR" "$TAILSCALE_DATA_DIR"
run_command bash -c "sudo chown pi:pi '$TAILSCALE_DIR' '$TAILSCALE_DATA_DIR'" > /dev/null 2>&1
echo "$SUCCESS Directories created."

# --- Section 4: User Input ---
if [ "$DUMMY_MODE" = true ]; then
	echo "[DEV MODE] Skipping user input and using dummy data."
	TS_HOSTNAME="ts-firewalla-test"
	TS_AUTHKEY="tskey-test-key"
	TS_EXTRA_ARGS=""
	ADVERTISED_ROUTES="192.168.0.0/24"
else
	read -p "$QUESTION Enter a hostname for this Tailscale node [ts-firewalla]: " TS_HOSTNAME
	TS_HOSTNAME=${TS_HOSTNAME:-ts-firewalla}

	while true; do
		read -p "$QUESTION Enter your Tailscale Auth Key (must start with 'tskey-'): " TS_AUTHKEY
		if [[ "$TS_AUTHKEY" == tskey-* ]]; then
			break
		else
			echo "$ERROR Invalid format. The Auth Key must start with 'tskey-'."
		fi
	done
	
	read -p "$QUESTION Do you want to use this device as a Tailscale exit node? (y/N): " USE_EXIT_NODE
 	if [[ "$USE_EXIT_NODE" =~ ^[Yy]$ ]]; then
		TS_EXIT_NODE_FLAG="--advertise-exit-node"
 		echo "$QUESTION This device will be configured as an exit node."
 	else
		TS_EXIT_NODE_FLAG=""
		echo "$INFO This device will not be configured as an exit node."
	fi
fi

# --- Section 5: Subnet Discovery ---
echo "$INFO Discovering available subnets..."
if [ "$DUMMY_MODE" = false ]; then
	readarray -t AVAILABLE_SUBNETS < <(get_available_subnets)

	if [ "${#AVAILABLE_SUBNETS[@]}" -eq 0 ]; then
		echo "$WARNING No bridge interfaces with subnets found. Subnet routing will be disabled."
		ADVERTISED_ROUTES=""
	else
		ADVERTISED_ROUTES=""
		SELECTED_INTERFACES=""
		for line in "${AVAILABLE_SUBNETS[@]}"; do
			interface=$(echo "$line" | awk '{print $1}')
			subnet=$(echo "$line" | awk '{print $2}')
			tailscale_subnet=$(convert_subnet_to_tailscale_format "$subnet")

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
				SELECTED_INTERFACES="$SELECTED_INTERFACES $interface"
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
	
    # Save selected interfaces to a file for the start script and uninstall script
    if [ -n "$SELECTED_INTERFACES" ]; then
        echo "$INFO Saving selected interfaces to $INTERFACES_FILE..."
        run_command sudo bash -c "echo '# This file contains the network interfaces selected during Tailscale installation.' > '$INTERFACES_FILE'"
        run_command sudo bash -c "echo '$SELECTED_INTERFACES' >> '$INTERFACES_FILE'"
        run_command sudo chmod 644 "$INTERFACES_FILE"
        run_command sudo chown pi:pi "$INTERFACES_FILE"
        echo "$SUCCESS Selected interfaces saved."
    fi
fi

# --- Section 6: docker-compose.yml ---
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

# --- Section 7: Start Script ---
echo "$INFO Creating and running Tailscale start script..."
START_SCRIPT_CONTENT=$(generate_tailscale_start "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXIT_NODE_FLAG}" "${TAILSCALE_DATA_DIR}" "${DOCKER_COMPOSE_FILE}" "${TEST_MODE}" "${CONFIRM_MODE}" "${DUMMY_MODE}" "${INTERFACES_FILE}")

if [ "$DUMMY_MODE" = true ] || [ "$TEST_MODE" = true ]; then
	echo "[DEV/TEST MODE] Would create $START_SCRIPT with the following content:"
	echo "${START_SCRIPT_CONTENT}"
	run_command sudo bash "$START_SCRIPT"
else
	if [ "$CONFIRM_MODE" = true ]; then
		echo "The following start script will be created at $START_SCRIPT:"
		echo "${START_SCRIPT_CONTENT}"
		read -p "Create this file and run it once? [y/N] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			echo "${START_SCRIPT_CONTENT}" | sudo tee "$START_SCRIPT" > /dev/null
			sudo chmod +x "$START_SCRIPT"
			echo "$SUCCESS Start script created. Running it now..."
			sudo bash "$START_SCRIPT"
		else
			echo "Skipping start script creation and execution."
		fi
	else
		echo "${START_SCRIPT_CONTENT}" | sudo tee "$START_SCRIPT" > /dev/null
		sudo chmod +x "$START_SCRIPT"
		echo "$SUCCESS Start script created. Running it now..."
		sudo bash "$START_SCRIPT"
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
echo "$INFO If you enabled the exit node, you will also need to authorize it in the Tailscale admin console."
echo ""
echo "$INFO For more detailed setup instructions, please visit the project's GitHub page: https://github.com/${GITHUB_REPO}"
echo ""
echo "$INFO You can run the uninstaller later with: sudo $UNINSTALL_SCRIPT"
echo "
