# 🚀 Firewalla Tailscale Docker Integration 🚀

## Purpose 
This project provides a set of bash scripts to easily install and uninstall Tailscale as a Docker container on your Firewalla device. This allows your Firewalla to act as a subnet router and/or exit node for your Tailscale network, enabling secure access to your local network from anywhere.

## Why Tailscale?
Firewalla comes with a no-subscription VPN which is amazing. Why do I need tailscale? 

Actually, Firealla has:
* **[VPN Server](https://help.firewalla.com/hc/en-us/articles/115004274633-Firewalla-VPN-Server):** allows you to access devices on your Firewalla-network when you are away.
* **[VPN Client](https://help.firewalla.com/hc/en-us/articles/360023379953-VPN-Client):** allows your Firealla to connect to another VPN server so your devices don't have to. Want to run your Apple TV through a VPN? just assign it to the VPN client.

So _why tailscale_? There are a many possible answers to this.

Tailscale is appealing because it works even if your ISP doesn’t give you a public IP. Many ISPs now place users behind Carrier-Grade NAT (CGNAT), making traditional VPNs like Firewalla’s difficult or impossible to set up. Tailscale handles this automatically, so you can connect to your home network from anywhere, even without a public IP. 

It also integrates seamlessly across all your devices. You don’t need to configure separate VPN clients or remember multiple setups—once a device joins your Tailscale network, it can securely connect to any other authorized device.

Finally, you don’t have to keep switching VPN software to connect different devices. Everything uses the same credentials and rules, making device-to-device access consistent and hassle-free.

Bottom line: Tailscale provides a unified, always-on private network that just works—no public IP, no complex VPN setup, and no juggling multiple clients.

 Tailscale has a [free tier](https://tailscale.com/pricing) with some limits. Problem solved!


## ✨ Features of this script

*   **Interactive Installation:** A guided setup process that makes configuration easy.
*   **Automatic Subnet Detection:** The script automatically detects your local subnets (LAN and VLANs) and asks which ones you want to make accessible through Tailscale.
*   **Simple Exit Node Setup:** A simple yes/no prompt to configure your Firewalla as an exit node.
*   **Clean Uninstallation:** A dedicated script to remove all traces of the Tailscale Docker setup.
*   **Minimal Impact:** Designed to integrate seamlessly with Firewalla's existing Docker environment without interference.

## 📝 Preparation

### Required
*   **A Firewalla device (only tested on Gold series for now).** 
*   **An active [Tailscale account](https://login.tailscale.com/start).**
*   **A Tailscale Auth Key.** You can generate one from your Tailscale admin console under **Settings** -> **Auth keys**. For more information, see [Tailscale's documentation on auth keys](https://tailscale.com/kb/1085/auth-keys/).
### Recommended
*   **A dedicated VLAN for Tailscale.** For enhanced security and control, we recommend creating a dedicated VLAN on your Firewalla for Tailscale. This creates a secure "landing zone" for all incoming Tailscale traffic, which you can then control with Firewalla's firewall rules. Using a VLAN also avoids consuming your Firewalla's port assignments in the same way a separate physical network might.
    *   In the Firewalla app, create a new LAN with a specific IP range. We suggest using a subnet with `100` as the third octet (e.g., `192.168.100.0/24`).
    *   It is okay to disable DHCP, mDNS, and SSDP on this new VLAN.
    *   This VLAN will be used to create rules in Firewalla to control Tailscale's access to the rest of your network. For example, you could allow just a device Group to be accessed by Tailscale using Firewalla's UI.

    Alternatively, if you prefer not to create a new VLAN, you can use an existing LAN or VLAN. In this case, you would identify the subnet of that existing network and the script will present it as an option to advertise.



## 🚀 Installation

[SSH to your firewalla. ](https://help.firewalla.com/hc/en-us/articles/115004397274-How-to-access-Firewalla-using-SSH)
To install Tailscale on your Firewalla, SSH into your Firewalla device and run the following command:

```bash
# replace this URL
curl -sSL 'https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh' | sudo bash
```

The script is interactive and will guide you through the following steps:

1.  **Tailscale Auth Key:** You will be prompted to enter your auth key.
2.  **Advertise Subnets:** The script will detect all the local subnets (LAN and VLANs) configured on your Firewalla. If you have created a dedicated VLAN with `.100.` in its third octet (e.g., `192.168.100.0/24`), the script will recommend this as the primary subnet to advertise. If you accept this, you may not need to advertise any other subnets. The script will then ask if you wish to advertise any other detected subnets.
3.  **Exit Node:** You will be asked if you want to use your Firewalla as an exit node.

Based on your answers, the script will automatically create the `docker-compose.yml` file, pull the container image, and start Tailscale for you.

### Advanced Usage

The `install.sh` script includes flags for more controlled execution:

*   **Test Mode (`-t`):** Run the script in test mode to see which commands would be executed without actually making any changes. This is useful for understanding what the script will do before you run it.

    ```bash
    curl -sSL https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh | sudo bash -s -- -t
    ```

*   **Confirm Mode (`-c`):** Run the script in confirm mode to be prompted for approval before each command is executed. This gives you fine-grained control over the installation process.

    ```bash
    curl -sSL https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh | sudo bash -s -- -c
    ```

### ➡️ Post-Installation Steps

After the installation script completes, you **must** perform the following steps in your Tailscale admin console:

1.  **Authorize Device:** Go to the [Machines page](https://login.tailscale.com/admin/machines) and authorize your newly added Firewalla device.
2.  **Enable Subnet Routes:** If you chose to advertise any subnets, you must enable them. Click the `...` menu next to your Firewalla device, select **Edit route settings...**, and enable the routes you want to use.

### 🚪 Configuring an Exit Node

An exit node allows you to route all of your internet traffic through your Firewalla, no matter where you are. This is useful for accessing the internet with your home IP address and for an extra layer of security when on public Wi-Fi.

The installation script will ask you if you want to configure your Firewalla as an exit node. If you answer yes, the script will automatically add the necessary `--advertise-exit-node` flag.

After the installation is complete, you **must** enable the exit node in your Tailscale admin console:

1.  **Enable Exit Node:** In the [Machines page](https://login.tailscale.com/admin/machines), click the `...` menu next to your Firewalla device and select **Edit route settings...**.
2.  **Enable the `Use as exit node` toggle.**

Once enabled, you can select your Firewalla as an exit node from the Tailscale client on your other devices. For more information, see the [Tailscale documentation on exit nodes](https://tailscale.com/kb/1019/subnets#exit-nodes).

## 🗑️ Uninstallation

To remove Tailscale from your Firewalla, SSH into your Firewalla device and run the uninstall script:

```bash
sudo /data/uninstall-tailscale-firewalla.sh
```

This script will stop and remove the Tailscale Docker container and image, delete the `docker-compose.yml` file, and clean up all associated directories and the uninstall script itself.

### Advanced Usage (Uninstall)

The `uninstall.sh` script also supports the `-t` and `-c` flags.

*   **Test Mode (`-t`):**
    ```bash
    sudo /data/uninstall-tailscale-firewalla.sh -t
    ```

*   **Confirm Mode (`-c`):**
    ```bash
    sudo /data/uninstall-tailscale-firewalla.sh -c
    ```

## 💡 How It Works

The installer script automates the process described in the [official Tailscale documentation for running in Docker](https://tailscale.com/kb/1282/docker). It detects your local networks and interactively helps you build the correct `--advertise-routes` and `--advertise-exit-node` arguments. It also includes the `--accept-dns=true` argument by default to allow Tailscale to manage DNS for your tailnet.

## 📚 References

*   [Tailscale: How to run Tailscale in Docker](https://tailscale.com/kb/1282/docker)
*   [Tailscale: Subnet routers and traffic relay nodes](https://tailscale.com/kb/1019/subnets)
*   [Reddit: Easy Tailscale integration via docker compose](https://www.reddit.com/r/firewalla/comments/1mlrtvi/easy_tailscale_integration_via_docker_compose/) (Credit to u/adrianmihalko for the original concept)

---
Made with 🔥 and ❤️  for the Firewalla Community! Not associated with or supported by Firewalla. 

