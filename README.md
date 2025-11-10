# Tailscale on Firewalla via Docker

🎉 Easily install and manage Tailscale on your Firewalla device using Docker! This project provides a simple bash script to set up Tailscale, allowing your Firewalla to act as a subnet router for your entire network.

## ✨ Features

*   **Easy Installation:** A single `curl` command to set up Tailscale.
*   **Dockerized:** Runs Tailscale in a Docker container, minimizing interference with your Firewalla's system.
*   **Subnet Routing:** Configures your Firewalla to advertise its local subnets to your Tailscale network.
*   **Exit Node Support:** Option to configure your Firewalla as a Tailscale exit node.
*   **Clean Uninstallation:** A separate script to completely remove Tailscale and its configurations.
*   **Firewalla-friendly:** Designed to integrate seamlessly with Firewalla's existing Docker environment.

## ⚠️ Important Note on Subnet Representation

When configuring subnet routes, Firewalla typically displays network addresses with a host IP (e.g., `192.168.10.1/24`). However, Tailscale requires the network address to end in `.0` (e.g., `192.168.10.0/24`).

This installer script automatically handles this conversion for you. When it discovers available subnets and asks if you want to advertise them, it will present them in the Tailscale-compatible `.0` format. You should approve these subnets as presented by the script.

## 🚀 Installation

To install Tailscale on your Firewalla, follow these steps:

1.  **SSH into your Firewalla:**
    ```bash
    ssh pi@your_firewalla_ip
    ```

2.  **Run the installation script:**
    ```bash
    curl -sL https://raw.githubusercontent.com/mbierman/tailscale-firewalla-docker/main/install.sh | sudo bash
    ```
    The script will guide you through the setup process, asking for a hostname, your Tailscale Auth Key, and which subnets you'd like to advertise.

3.  **Authorize Subnet Routes in Tailscale Admin Console:**
    After installation, you **must** authorize the subnet routes in your Tailscale admin console.
    *   Go to [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
    *   Find your Firewalla device (using the hostname you provided during installation).
    *   Click the "..." menu next to your device and select "Edit route settings...".
    *   Approve the subnet route(s) that correspond to your local network(s).

## 🗑️ Uninstallation

To completely remove Tailscale from your Firewalla, run the uninstall script:

```bash
sudo /data/tailscale-uninstall.sh
```

This will stop and remove the Docker container, delete all associated files and directories, and revert any system-level changes made by the installer.

## 🛠️ Development & Contribution

(Placeholder for future development and contribution guidelines)

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
