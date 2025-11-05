# 🚀 Firewalla Tailscale Docker Integration 🚀

This project provides a set of bash scripts to easily install and uninstall Tailscale as a Docker container on your Firewalla device. This allows your Firewalla to act as a subnet router and/or exit node for your Tailscale network, enabling secure access to your local network from anywhere.

## ✨ Features

*   **Interactive Installation:** A guided setup process that makes configuration easy.
*   **Automatic Subnet Detection:** The script automatically detects your local subnets (LAN and VLANs) and asks which ones you want to make accessible through Tailscale.
*   **Simple Exit Node Setup:** A simple yes/no prompt to configure your Firewalla as an exit node.
*   **Clean Uninstallation:** A dedicated script to remove all traces of the Tailscale Docker setup.
*   **Minimal Impact:** Designed to integrate seamlessly with Firewalla's existing Docker environment without interference.

## 📝 Prerequisites

*   A Firewalla device (only test Gold series for now).
*   An active Tailscale account.
*   A Tailscale Auth Key. You can generate a reusable one from your Tailscale admin console under **Settings** -> **Auth keys**. For more information, see [Tailscale's documentation](https://tailscale.com/kb/1085/auth-keys/).

## 🚀 Installation

[SSH to your firewalla. ](https://help.firewalla.com/hc/en-us/articles/115004397274-How-to-access-Firewalla-using-SSH)
To install Tailscale on your Firewalla, SSH into your Firewalla device and run the following command:

```bash
curl -sSL https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh | sudo bash
```

The script is interactive and will guide you through the following steps:

1.  **Tailscale Auth Key:** You will be prompted to enter your auth key.
2.  **Advertise Subnets:** The script will detect all the local subnets (LAN and VLANs) configured on your Firewalla and ask you, one by one, if you wish to advertise them on your Tailscale network.
3.  **Exit Node:** You will be asked if you want to use your Firewalla as an exit node.

Based on your answers, the script will automatically create the `docker-compose.yml` file, pull the container image, and start Tailscale for you.

### ➡️ Post-Installation Steps

After the installation script completes, you **must** perform the following steps in your Tailscale admin console:

1.  **Authorize Device:** Go to the [Machines page](https://login.tailscale.com/admin/machines) and authorize your newly added Firewalla device.
2.  **Enable Subnet Routes:** If you chose to advertise any subnets, you must enable them. Click the `...` menu next to your Firewalla device, select **Edit route settings...**, and enable the routes you want to use.
3.  **Enable Exit Node:** If you chose to enable the exit node, you must also enable it from the **Edit route settings...** menu for the Firewalla device.

## 🗑️ Uninstallation

To remove Tailscale from your Firewalla, SSH into your Firewalla device and run the uninstall script:

```bash
sudo /data/uninstall-tailscale-firewalla.sh
```

This script will stop and remove the Tailscale Docker container, delete the `docker-compose.yml` file, and clean up all associated directories and the uninstall script itself.

## 💡 How It Works

The installer script automates the process described in the [official Tailscale documentation for running in Docker](https://tailscale.com/kb/1282/docker). It detects your local networks and interactively helps you build the correct `--advertise-routes` and `--advertise-exit-node` arguments. It also includes the `--accept-dns=true` argument by default to allow Tailscale to manage DNS for your tailnet.

## 📚 References

*   [Tailscale: How to run Tailscale in Docker](https://tailscale.com/kb/1282/docker)
*   [Tailscale: Subnet routers and traffic relay nodes](https://tailscale.com/kb/1019/subnets)
*   [Reddit: Easy Tailscale integration via docker compose](https://www.reddit.com/r/firewalla/comments/1mlrtvi/easy_tailscale_integration_via_docker_compose/) (Credit to u/adrianmihalko for the original concept)

---
Made with 🔥 and ❤️  for the Firewalla Community!
