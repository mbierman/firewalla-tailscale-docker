# Tailscale for Firewalla

🎉 Easily install and manage Tailscale on your Firewalla device using Docker! This project provides a simple bash script to set up Tailscale, allowing your Firewalla to act as a subnet router for your entire network.

## ✨ Features

*   **Automated Installation:** A single script handles Docker Compose setup, Tailscale container deployment, and IP forwarding configuration.
*   **Subnet Routing:** Configure your Firewalla to advertise local subnets to your Tailscale network.
*   **Exit Node Support:** Optionally configure your Firewalla as an exit node for your Tailscale network.
*   **Easy Uninstallation:** A separate script to cleanly remove all Tailscale components.
*   **Firewalla Friendly:** Designed to integrate seamlessly with Firewalla's existing Docker environment.

## 🚀 Installation

To install Tailscale on your Firewalla, simply run the following command in your Firewalla's SSH terminal:

```bash
curl -sfL https://raw.githubusercontent.com/mbierman/tailscale-firewalla/main/github/install.sh | sudo bash
```

The script will:
1.  **Prompt for a hostname** for your Tailscale node (e.g., `firewalla-ts`).
2.  **Ask for your Tailscale Auth Key** (starts with `tskey-`). You can generate one from your [Tailscale admin console](https://login.tailscale.com/admin/settings/authkeys).
3.  **Ask if you want to enable Exit Node functionality.**
4.  **Discover available subnets** on your Firewalla and ask if you want to advertise them to your Tailscale network.
5.  **Create the `docker-compose.yml`** file in `/home/pi/.firewalla/run/docker/tailscale`.
6.  **Pull the Tailscale Docker image** and start the container.
7.  **Enable IP forwarding** persistently on your Firewalla.

### ⚠️ Important Post-Installation Steps

After the installation is complete, you **must** authorize the subnet routes in your Tailscale admin console:

1.  Go to your Tailscale Admin Console: [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2.  Find the device corresponding to the hostname you provided during installation.
3.  Click the `...` menu next to the device and select `Edit route settings...`.
4.  Enable the advertised subnet route(s) to allow access to your local network via Tailscale.

## 🗑️ Uninstallation

To remove Tailscale from your Firewalla, run the uninstall script:

```bash
sudo /data/tailscale-uninstall.sh
```

The uninstall script will:
1.  Stop and remove the Tailscale Docker container and its associated volumes.
2.  Remove the Tailscale configuration and data directories.
3.  Remove the persistent IP forwarding configuration.
4.  Remove the uninstall script itself.

### 🧹 Manual Cleanup (if necessary)

If the uninstall script encounters issues, you may need to manually remove the device from your [Tailscale admin console](https://login.tailscale.com/admin/machines).

## 🤝 Contributing

Contributions are welcome! If you have suggestions for improvements or bug fixes, please open an issue or submit a pull request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.