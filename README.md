# 🚀 Tailscale Installer for Firewalla

This repository provides a convenient bash script to install and configure [Tailscale](https://tailscale.com/) on your Firewalla device using Docker. This setup allows your Firewalla to act as a subnet router, enabling any device on your local network to access your Tailscale network, and optionally as an exit node.

## ✨ Features

*   **Easy Installation:** A single `curl` command to get Tailscale up and running.
*   **Subnet Routing:** Automatically discovers and advertises your Firewalla's local subnets to your Tailscale network, allowing access to your LAN devices.
*   **Exit Node Support:** Optionally configure your Firewalla as an exit node for your Tailscale network.
*   **Dockerized:** Runs Tailscale in a Docker container, minimizing interference with your Firewalla's system.
*   **Clean Uninstallation:** A separate script to completely remove Tailscale and its configurations.
*   **Persistent Configuration:** Ensures IP forwarding and Tailscale data persist across reboots.

## ⚠️ Prerequisites

*   **Firewalla Device:** This script is designed for Firewalla Gold/Purple series devices.
*   **SSH Access:** You need to be able to SSH into your Firewalla as the `pi` user.
*   **Docker:** Docker and `docker compose` (or `docker-compose`) must be installed on your Firewalla. Firewalla devices typically come with Docker pre-installed.
*   **Tailscale Account:** A free or paid Tailscale account is required.
*   **Tailscale Auth Key:** You will need a valid Tailscale authentication key for unattended node registration. Generate one from your [Tailscale admin console](https://login.tailscale.com/admin/settings/authkeys).

## 🚀 Installation

To install Tailscale, simply run the following command on your Firewalla via SSH:

```bash
curl -sL https://raw.githubusercontent.com/mbierman/tailscale-firewalla/main/github/install.sh | sudo bash
```

The script will:
1.  Download the `uninstall.sh` script to `/data/tailscale-uninstall.sh`.
2.  Create necessary directories (`/home/pi/.firewalla/run/docker/tailscale` and `/data/tailscale`).
3.  Prompt you for a hostname for your Tailscale node and your Tailscale Auth Key.
4.  Ask if you want to configure the Firewalla as an exit node.
5.  Automatically discover and configure subnet routes for your local networks.
6.  Create the `docker-compose.yml` file.
7.  Enable persistent IP forwarding.
8.  Pull the latest Tailscale Docker image and start the container.
9.  Provide instructions on how to authorize the subnet routes in your Tailscale admin console.

### Post-Installation Steps (Important! 🚨)

After the script completes, you **must** authorize the subnet routes in your Tailscale admin console:

1.  Go to your [Tailscale Admin Console](https://login.tailscale.com/admin/machines).
2.  Find the device with the hostname you provided during installation (e.g., `ts-firewalla`).
3.  Click the "..." menu next to the device and select "Edit route settings...".
4.  Enable the advertised subnet routes (e.g., `192.168.1.0/24`) and save.

Your Firewalla and its connected local network devices should now be accessible via Tailscale!

## 🗑️ Uninstallation

To completely remove Tailscale and its configurations, run the uninstall script that was downloaded during installation:

```bash
sudo /data/tailscale-uninstall.sh
```

The script will:
1.  Stop and remove the Tailscale Docker container and its associated volumes.
2.  Remove the Tailscale configuration and data directories.
3.  Remove the persistent IP forwarding configuration.
4.  Remove the uninstall script itself.

You may also want to manually remove the Firewalla device from your [Tailscale admin console](https://login.tailscale.com/admin/machines) if it's still listed.

## ❓ Why Subnet Routing?

Tailscale's subnet routing feature allows your Firewalla to act as a gateway to your local network. This means that any device connected to your Firewalla's LAN can be accessed from your Tailscale network, even if those devices don't have Tailscale installed themselves. This is ideal for accessing smart home devices, network-attached storage (NAS), or other local services securely from anywhere.

## 📚 Tailscale Documentation

*   [Tailscale Docker Guide](https://tailscale.com/kb/1282/docker)
*   [Subnet Routers](https://tailscale.com/kb/1019/subnets)
*   [Exit Nodes](https://tailscale.com/kb/1103/exit-nodes)

## 🤝 Contributing

Feel free to open issues or pull requests if you have suggestions or improvements!

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.