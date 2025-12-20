#!/bin/bash
set -x
set -e
set -o pipefail

# Emoji for user-facing output
INFO="ℹ️ "
QUESTION="❔"
SUCCESS="✅ "
WARNING="⚠️ "
ERROR="❌ "
VERSION="1.5.0 "

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
CONFIG_FILE="/data/tailscale.conf"
START_SCRIPT="/home/pi/.firewalla/config/post_main.d/tailscale-start.sh"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-tailscale.conf"
UNINSTALL_SCRIPT="/data/tailscale-uninstall.sh"
GITHUB_REPO="mbierman/firewalla-tailscale-docker"
LATEST_UNINSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/uninstall.sh?t=$(date +%s)"
check_url_exists "$LATEST_UNINSTALL_SCRIPT_URL"

# --- Functions ---

# Function to execute or display commands
run_command() {
	if [ "$DUMMY_MODE" = true ]; then
		echo "[DEV MODE] Would run: $@"
	elif [ "$TEST_MODE" = true ]; then
		echo "[TEST MODE] Would run: $@"
	elif [ "$CONFIRM_MODE" = true ]; then
		read -p "Run this command? '$@' [y/N] " -n 1 -r < /dev/tty
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

# Function to check for and start Docker if not running
check_and_start_docker() {
	echo "$INFO Checking Docker status..."

	# In test or dummy mode, we can't rely on the service status.
	# We'll just show what would happen and not actually check or wait.
	if [ "$TEST_MODE" = true ] || [ "$DUMMY_MODE" = true ]; then
		echo "[DEV/TEST MODE] Assuming Docker is not running to show full logic."
		run_command sudo systemctl enable docker
		run_command sudo systemctl start docker
		echo "[DEV/TEST MODE] Would wait for Docker to become ready."
		return
	fi

	# This part runs only in normal or confirm mode
	if sudo systemctl is-active --quiet docker; then
		echo "$SUCCESS Docker is already running."
		return
	fi

	echo "$WARNING Docker is not running. Attempting to start it..."
	run_command sudo systemctl enable docker
	run_command sudo systemctl start docker

	echo "$INFO Waiting for Docker daemon to become ready..."
	local timeout=30
	local start_time=$(date +%s)

	while [ ! -S /var/run/docker.sock ]; do
		local current_time=$(date +%s)
		local elapsed_time=$((current_time - start_time))

		if [ "$elapsed_time" -ge "$timeout" ]; then
			echo "$ERROR Timed out waiting for Docker to start. Please check your system for issues."
			exit 1
		fi
		sleep 1
	done

	if sudo systemctl is-active --quiet docker; then
		echo "$SUCCESS Docker started successfully."
	else
		# This case should be rare if the socket is up, but it's a good final check.
		echo "$ERROR Docker socket is present, but the service is not active. Please investigate."
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
version: "3.3"
services:
  tailscale:
    container_name: tailscale
    image: tailscale/tailscale:latest
    network_mode: host
    privileged: true
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    volumes:
      - ${TAILSCALE_DATA_DIR}:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    logging:
      driver: "json-file"
      options:
        max-size: "5mb"
        max-file: "3"
    command: tailscaled --tun=userspace-networking
    healthcheck:
      test: ["CMD-SHELL", "tailscale status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 256M
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
	local CONFIG_FILE="${10}"
	local GITHUB_REPO_VAR="${11}" # Renamed to avoid conflict with global GITHUB_REPO

# The script content generated below uses the local variables above
cat <<-EOF
#!/bin/bash
set -e

# --- User-Friendliness Guard ---
# Check if the script is being run with the -R flag by mistake.
if [ "\$1" == "-R" ]; then
	echo "❌ ERROR: You have run the startup script (tailscale-start.sh) with the -R flag."
	echo "The -R flag is for re-authenticating and should be used with the main installer script."
	echo ""
	echo "To re-authenticate your Tailscale node, please run the following command:"
	echo "curl -sSL \\"https://raw.githubusercontent.com/${GITHUB_REPO_VAR}/main/install.sh?t=\$(date +%s)\\" | sudo bash -s -- -R"
	echo ""
	exit 1
fi

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
		read -p "Run this command? '\$@' [y/N] " -n 1 -r < /dev/tty
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

# Source the persistent configuration file to get TS_INTERFACES
if [ -f "${CONFIG_FILE}" ]; then
	source "${CONFIG_FILE}"
fi

# Add NAT rule(s)
OLD_IFS="\$IFS"
IFS=','
for iface in \$TS_INTERFACES; do
	# Trim leading/trailing whitespace from iface
	iface=\$(echo "\$iface" | xargs)
	if ! sudo iptables -t nat -C POSTROUTING -s 100.64.0.0/10 -o "\$iface" -j MASQUERADE 2>/dev/null; then
		echo "Creating iptable NAT rule for \$iface..."
		run_command sudo iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -o "\$iface" -j MASQUERADE
	else
		echo "IP table NAT rule for \$iface already in place."
	fi
	
	sleep 2
done
IFS="\$OLD_IFS"

# Wait for Docker socket to be available
echo "Waiting for Docker daemon..."
while [ ! -S /var/run/docker.sock ]; do
	sleep 1
done
echo "Docker daemon is ready."

# Start the container
docker_compose_command -f $DOCKER_COMPOSE_FILE up -d

# Loop until the container is running, with a timeout
echo "Waiting for the container to start..."
container_timeout=60
container_start_time=\$(date +%s)
while ! sudo docker ps -q -f name=tailscale | grep -q .; do
	current_time=\$(date +%s)
	elapsed_time=\$((current_time - container_start_time))

	if [ "\$elapsed_time" -ge "\$container_timeout" ]; then
		echo "ERROR: Timed out waiting for Tailscale container to start."
		echo "Please check the container logs for errors: sudo docker logs tailscale"
		exit 1
	fi
	echo "Container not ready, waiting 5 seconds..."
	sleep 5
done
echo "Container started."

# Wait a few seconds for tailscaled to initialize
sleep 3
EOF
}

# Function to validate hostname, providing specific error messages
validate_hostname() {
    local hostname="$1"
    
    # Rule 1: Cannot be empty
    if [ -z "$hostname" ]; then
        echo "$ERROR Hostname cannot be empty."
        return 1
    fi

    # Rule 2: No spaces
    if [[ "$hostname" =~ " " ]]; then
        echo "$ERROR Hostname '$hostname' is invalid: Spaces are not allowed. Use a hyphen '-' instead."
        return 1
    fi

    # Rule 3: No underscores
    if [[ "$hostname" =~ "_" ]]; then
        echo "$ERROR Hostname '$hostname' is invalid: Underscores '_' are not allowed. Use a hyphen '-' instead."
        return 1
    fi

    # Rule 4: No special characters or punctuation (excluding hyphens)
    if [[ "$hostname" =~ [^a-zA-Z0-9\-] ]]; then
        echo "$ERROR Hostname '$hostname' is invalid: Contains special characters or punctuation."
        echo "$INFO Only letters (a-z, A-Z), numbers (0-9), and hyphens (-) are allowed."
        return 1
    fi

    # Rule 5: Cannot start or end with a hyphen
    if [[ "$hostname" == -* ]] || [[ "$hostname" == *- ]]; then
        echo "$ERROR Hostname '$hostname' is invalid: Cannot start or end with a hyphen."
        return 1
    fi

    # Rule 6: No Emojis/Unicode (Only ASCII)
    # Use grep with Perl-compatible regex to find any non-ASCII characters.
    if echo "$hostname" | grep -qP '[^\x00-\x7F]'; then
        echo "$ERROR Hostname '$hostname' is invalid: Contains Emojis or other non-ASCII characters."
        echo "$INFO Only standard ASCII characters are permitted."
        return 1
    fi

    return 0 # All checks passed, hostname is valid
}

# --- Command-line flags ---
TEST_MODE=false    # Test, but doesn't do anything
CONFIRM_MODE=false # Ask before doing
DUMMY_MODE=false
TS_EXIT_NODE_FLAG="true"   # Initialize TS_EXIT_NODE_FLAG
REAUTH_MODE=false
UPDATE_MODE=false

while getopts "tcdRu" opt; do
	case ${opt} in
		t) TEST_MODE=true ;;
		c) CONFIRM_MODE=true ;;
		d) DUMMY_MODE=true ;;
		R) REAUTH_MODE=true ;;
		u) UPDATE_MODE=true ;;
		*) echo "Invalid option: -${OPTARG}" >&2; exit 1 ;;
	esac
done
shift $((OPTIND -1))

# Check for mutually exclusive flags
if [ "$TEST_MODE" = true ] && [ "$DUMMY_MODE" = true ]; then
	echo "$ERROR The -t (test) and -d (dummy) flags are mutually exclusive. Please use one or the other."
	exit 1
fi

if [ "$UPDATE_MODE" = true ]; then
	# --- UPDATE LOGIC ---
	echo "$INFO Starting Tailscale container update check..."

	if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
		echo "$ERROR Docker compose file not found at $DOCKER_COMPOSE_FILE."
		echo "$INFO Cannot update. Please run the full installation first."
		exit 1
	fi

	check_and_start_docker

	echo "$INFO Checking for a newer version of the Tailscale image..."
	# Get the image ID before pulling
	BEFORE_ID=$(sudo docker images --format "{{.ID}}" tailscale/tailscale:latest 2>/dev/null || echo "notfound")

	# Pull the latest image
	docker_compose_command -f "$DOCKER_COMPOSE_FILE" pull

	# Get the image ID after pulling
	AFTER_ID=$(sudo docker images --format "{{.ID}}" tailscale/tailscale:latest 2>/dev/null || echo "notfound")
	
	if [ "$BEFORE_ID" == "$AFTER_ID" ]; then
		echo "$SUCCESS Tailscale is already up to date. No action needed."
	else
		echo "$INFO New image downloaded. Applying update..."
		docker_compose_command -f "$DOCKER_COMPOSE_FILE" up -d
		echo "$SUCCESS Container has been updated successfully!"
	fi

	exit 0
fi

if [ "$REAUTH_MODE" = true ]; then
	# --- RE-AUTHENTICATION LOGIC ---
	echo "$INFO Starting Tailscale re-authentication..."

	if [ ! -f "$CONFIG_FILE" ]; then
		echo "$ERROR Configuration file not found at $CONFIG_FILE."
		echo "$INFO Cannot re-authenticate. Please run the full installation first."
		exit 1
	fi

	source "$CONFIG_FILE"
	check_and_start_docker

	echo "$INFO Reading existing configuration..."
	ADVERTISED_ROUTES=""
	if [ -n "$TS_INTERFACES" ]; then
		SUBNET_LIST=$(get_available_subnets)
		OLD_IFS="$IFS"
		IFS=',' # Set IFS to comma to split TS_INTERFACES
		for iface in $TS_INTERFACES; do
			# Trim leading/trailing whitespace from iface
			iface=$(echo "$iface" | xargs)
			subnet_line=$(echo "$SUBNET_LIST" | grep -w "$iface")
			if [ -n "$subnet_line" ]; then
				subnet=$(echo "$subnet_line" | awk '{print $2}')
				tailscale_subnet=$(convert_subnet_to_tailscale_format "$subnet")
				if [ -z "$ADVERTISED_ROUTES" ]; then
					ADVERTISED_ROUTES="$tailscale_subnet"
				else
					ADVERTISED_ROUTES="$ADVERTISED_ROUTES,$tailscale_subnet"
				fi
			fi
		done
		IFS="$OLD_IFS" # Restore original IFS
	fi
	echo "$SUCCESS Found hostname: $TS_HOSTNAME"
	if [ -n "$ADVERTISED_ROUTES" ]; then
		echo "$SUCCESS Reconstructed advertised routes: $ADVERTISED_ROUTES"
	fi

	while true; do
		 read -p "$QUESTION Enter your Tailscale Auth Key (must start with 'tskey-auth-'): " TS_AUTHKEY < /dev/tty
		 if [[ "$TS_AUTHKEY" == tskey-auth-* ]]; then
			 break
		 else
			 echo "$ERROR Invalid format. The Auth Key must start with 'tskey-auth-'."
		 fi
	done


	if [ -n "$TS_EXIT_NODE_FLAG" ]; then
		echo "$SUCCESS Exit node flag: $TS_EXIT_NODE_FLAG"
	else
		echo "$INFO Exit node not configured."
	fi

	echo "$INFO Performing re-authentication..."
	run_command sudo docker exec tailscale tailscale up \
		--authkey="${TS_AUTHKEY}" \
		--hostname="${TS_HOSTNAME}" \
		--advertise-routes="${ADVERTISED_ROUTES}" \
		${TS_EXIT_NODE_FLAG} \
		--accept-routes \
		--accept-dns \
		--reset &

	echo "$SUCCESS Re-authentication complete! 🎉"
	exit 0
fi

# --- Script Start ---

echo "$INFO Starting Tailscale installation for Firewalla (v$VERSION)..."

# Check and start Docker if not running
check_and_start_docker

# --- Section 2: Uninstall Script ---
echo "$INFO Checking for uninstall script..."
LOCAL_VERSION=""
if [ -f "$UNINSTALL_SCRIPT" ]; then
	LOCAL_VERSION=$(grep -m 1 '# VERSION:' "$UNINSTALL_SCRIPT" | cut -d':' -f2 || true)
fi

TEMP_UNINSTALL_SCRIPT=""
# Create a temporary file and ensure it's cleaned up on exit
trap 'rm -f "$TEMP_UNINSTALL_SCRIPT"' EXIT
TEMP_UNINSTALL_SCRIPT=$(mktemp)

if ! curl -sL "$LATEST_UNINSTALL_SCRIPT_URL" -o "$TEMP_UNINSTALL_SCRIPT"; then
	echo "$WARNING Could not fetch remote uninstall script. Will proceed without updating."
	REMOTE_VERSION=""
else
	REMOTE_VERSION=$(grep -m 1 '# VERSION:' "$TEMP_UNINSTALL_SCRIPT" | cut -d':' -f2 || true)
fi

if [ -z "$REMOTE_VERSION" ]; then
	echo "$WARNING Could not determine remote uninstall script version. Skipping update check."
elif [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
	echo "$INFO New uninstall script version ($REMOTE_VERSION) found. Updating..."
	run_command sudo cp "$TEMP_UNINSTALL_SCRIPT" "$UNINSTALL_SCRIPT"
	run_command sudo chmod +x "$UNINSTALL_SCRIPT"
	run_command sudo chown pi:pi "$UNINSTALL_SCRIPT"
	echo "$SUCCESS Uninstall script updated to version $REMOTE_VERSION."
else
	echo "$SUCCESS Uninstall script is already up to date (v$LOCAL_VERSION)."
fi

# The trap will clean up the temp file
trap - EXIT
rm -f "$TEMP_UNINSTALL_SCRIPT"

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
	ADVERTISED_ROUTES="192.168.0.0/24"
else
	while true; do
		read -p "$QUESTION Enter a hostname for this Tailscale node [ts-firewalla]: " TS_HOSTNAME_INPUT < /dev/tty
		TS_HOSTNAME=${TS_HOSTNAME_INPUT:-ts-firewalla}

		if validate_hostname "$TS_HOSTNAME"; then
			echo "$SUCCESS Hostname '$TS_HOSTNAME' is valid."
			break # Exit loop if hostname is valid
		else
			# The function already printed the specific error
			echo "$INFO Please try again."
		fi
	done

	if [ "$TEST_MODE" = true ]; then
	    echo "$INFO Hostname is set to: $TS_HOSTNAME"
	fi

	while true; do
		read -p "$QUESTION Enter your Tailscale Auth Key (must start with 'tskey-auth-'): " TS_AUTHKEY < /dev/tty
		if [[ "$TS_AUTHKEY" == tskey-* ]]; then
			break
		else
			echo "$ERROR Invalid format. The Auth Key must start with 'tskey-auth-'."
		fi
	done
	
	read -p "$QUESTION Do you want to use this device as a Tailscale exit node? (Y/n): " USE_EXIT_NODE < /dev/tty
	if [[ -z "$USE_EXIT_NODE" || "$USE_EXIT_NODE" =~ ^[Yy]$ ]]; then
		TS_EXIT_NODE_FLAG="--advertise-exit-node"
		echo "$INFO This device will be configured as an exit node."
	else
		TS_EXIT_NODE_FLAG=""
		echo "$INFO This device will not be configured as an exit node."
	fi
fi

# --- IPv6 Prompt ---
ENABLE_IPV6="n" # Default to no
if [ "$DUMMY_MODE" = false ]; then
	read -p "$QUESTION Do you want to enable IPv6 forwarding for Tailscale? (y/N): " ENABLE_IPV6 < /dev/tty
fi

# --- Section 1: IP Forwarding ---
echo "$INFO Configuring persistent IP forwarding..."
if [ "$TEST_MODE" = true ] || [ "$CONFIRM_MODE" = true ]; then
	run_command echo "Write 'net.ipv4.ip_forward=1' to $SYSCTL_CONF_FILE"
	if [[ "$ENABLE_IPV6" =~ ^[Yy]$ ]]; then
		run_command echo "Write 'net.ipv6.conf.all.forwarding=1' to $SYSCTL_CONF_FILE"
	fi
	run_command sudo sysctl -p "$SYSCTL_CONF_FILE"
else
	# Build the sysctl configuration content
	SYSCTL_CONTENT="net.ipv4.ip_forward=1"
	# Add buffer size optimizations for WireGuard/Tailscale performance
	SYSCTL_CONTENT="${SYSCTL_CONTENT}\nnet.core.rmem_max=2500000"
	SYSCTL_CONTENT="${SYSCTL_CONTENT}\nnet.core.wmem_max=2500000"
	if [[ "$ENABLE_IPV6" =~ ^[Yy]$ ]]; then
		SYSCTL_CONTENT="${SYSCTL_CONTENT}\nnet.ipv6.conf.all.forwarding=1"
		echo "$INFO IPv6 forwarding has been enabled."
	else
		echo "$INFO IPv6 forwarding is disabled."
	fi

	# Create the directory and write the configuration file, overwriting any existing file
	sudo mkdir -p "$(dirname "$SYSCTL_CONF_FILE")"
	echo -e "$SYSCTL_CONTENT" | sudo tee "$SYSCTL_CONF_FILE" > /dev/null

	# Apply the new settings
	sudo sysctl -p "$SYSCTL_CONF_FILE"
	echo "$SUCCESS IP forwarding settings configured."
fi

# --- Section 5: Subnet Discovery ---
echo "$INFO Discovering available subnets..."
ADVERTISED_ROUTES=""
SELECTED_INTERFACES=""
if [ "$DUMMY_MODE" = false ]; then
	SUBNET_LIST=$(get_available_subnets)

	if [ -z "$SUBNET_LIST" ]; then
		echo "$WARNING No bridge interfaces with subnets found. Subnet routing will be disabled."
	else
		OLD_IFS="$IFS"
		IFS=$'\n'
		for line in $SUBNET_LIST; do
			if [ -z "$line" ]; then continue; fi
			interface=$(echo "$line" | awk '{print $1}')
			subnet=$(echo "$line" | awk '{print $2}')
			tailscale_subnet=$(convert_subnet_to_tailscale_format "$subnet")

			read -p "$QUESTION Do you want to advertise the subnet $tailscale_subnet? (y/N): " ADVERTISE_SUBNET < /dev/tty

			if [[ "$ADVERTISE_SUBNET" =~ ^[Yy]$ ]]; then
				if [ -z "$ADVERTISED_ROUTES" ]; then
					ADVERTISED_ROUTES="$tailscale_subnet"
				else
					ADVERTISED_ROUTES="$ADVERTISED_ROUTES,$tailscale_subnet"
				fi
				if [ -z "$SELECTED_INTERFACES" ]; then
					SELECTED_INTERFACES="$interface"
				else
					SELECTED_INTERFACES="$SELECTED_INTERFACES,$interface"
				fi
				echo "$SUCCESS Subnet $tailscale_subnet will be advertised."
			else
				echo "$INFO Subnet $tailscale_subnet will NOT be advertised."
			fi
		done
		IFS="$OLD_IFS"

		if [ -z "$ADVERTISED_ROUTES" ]; then
			echo "$WARNING No subnets selected for advertisement."
		else
			echo "$SUCCESS Will advertise the following subnets: $ADVERTISED_ROUTES"
		fi
	fi
	
	# Create persistent configuration file
	echo "$INFO Creating persistent configuration file..."
	CONFIG_CONTENT="# This file stores persistent configuration for the Tailscale script.\n"
	CONFIG_CONTENT="${CONFIG_CONTENT}TS_HOSTNAME=\"${TS_HOSTNAME}\"\n"
	# Note: SELECTED_INTERFACES is a comma-delimited
	CONFIG_CONTENT="${CONFIG_CONTENT}TS_INTERFACES=\"${SELECTED_INTERFACES}\"\n"
	CONFIG_CONTENT="${CONFIG_CONTENT}TS_EXIT_NODE_FLAG=\"${TS_EXIT_NODE_FLAG}\"\n"

	run_command sudo bash -c "echo -e '$CONFIG_CONTENT' > '$CONFIG_FILE'"
	run_command sudo chmod 644 "$CONFIG_FILE"
	run_command sudo chown pi:pi "$CONFIG_FILE"
	echo "$SUCCESS Configuration saved to $CONFIG_FILE."
fi

# --- Section 6: docker-compose.yml ---
echo "$INFO Creating docker-compose.yml file..."
if [ "$DUMMY_MODE" = true ]; then
	echo "[DEV MODE] Would create $DOCKER_COMPOSE_FILE with the following content:"
	generate_docker_compose_yml
elif [ "$TEST_MODE" = true ]; then
	echo "[TEST MODE] Would create $DOCKER_COMPOSE_FILE with the following content:"
	generate_docker_compose_yml
elif [ "$CONFIRM_MODE" = true ]; then
	COMPOSE_CONTENT=$(generate_docker_compose_yml)
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
	generate_docker_compose_yml | sudo tee "$DOCKER_COMPOSE_FILE" > /dev/null
	echo "$SUCCESS docker-compose.yml created."
fi

# --- Section 7: Start Script ---
echo "$INFO Creating and running Tailscale start script..."
START_SCRIPT_CONTENT=$(generate_tailscale_start "${TS_HOSTNAME}" "${TS_AUTHKEY}" "${ADVERTISED_ROUTES}" "${TS_EXIT_NODE_FLAG}" "${TAILSCALE_DATA_DIR}" "${DOCKER_COMPOSE_FILE}" "${TEST_MODE}" "${CONFIRM_MODE}" "${DUMMY_MODE}" "${CONFIG_FILE}" "${GITHUB_REPO}")

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
			run_command sudo mkdir -p "$(dirname "$START_SCRIPT")"
			echo "${START_SCRIPT_CONTENT}" | sudo tee "$START_SCRIPT" > /dev/null
			sudo chmod +x "$START_SCRIPT"
			echo "$SUCCESS Start script created. Running it now..."
			sudo bash "$START_SCRIPT"

			echo "$INFO Waiting for container to initialize..."
			sleep 5
			echo "$INFO Performing one-time authentication..."
			run_command sudo docker exec tailscale tailscale up \
				--authkey="${TS_AUTHKEY}" \
				--hostname="${TS_HOSTNAME}" \
				--advertise-routes="${ADVERTISED_ROUTES}" \
				${TS_EXIT_NODE_FLAG} \
				--accept-routes \
				--accept-dns \
				--reset &
		else
			echo "Skipping start script creation and execution."
		fi
	else
		run_command sudo mkdir -p "$(dirname "$START_SCRIPT")"
		echo "${START_SCRIPT_CONTENT}" | sudo tee "$START_SCRIPT" > /dev/null
		sudo chmod +x "$START_SCRIPT"
		echo "$SUCCESS Start script created. Running it now..."
		sudo bash "$START_SCRIPT"

		echo "$INFO Waiting for container to initialize..."
		sleep 5
		echo "$INFO Performing one-time authentication..."
		run_command sudo docker exec tailscale tailscale up \
			--authkey="${TS_AUTHKEY}" \
			--hostname="${TS_HOSTNAME}" \
			--advertise-routes="${ADVERTISED_ROUTES}" \
			${TS_EXIT_NODE_FLAG} \
			--accept-routes \
			--accept-dns \
			--reset &
	fi
fi



# 9. Final Instructions
echo ""
echo "$SUCCESS Tailscale installation is complete! 🎉"
echo ""
echo "$INFO The Tailscale node on your Firewalla has been pre-authenticated with the key you provided."
echo "$INFO It should appear in your Tailscale admin console shortly."
echo "$INFO To approve your machine, visit (as admin):"
echo "$INFO 	https://login.tailscale.com/admin"
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
echo ""
