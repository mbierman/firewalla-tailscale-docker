# 🚀 Firewalla Tailscale Docker Integration via Docker

## Purpose 
🎉 Easily install and manage Tailscale on your Firewalla device using Docker! This project provides an easy installer to set up Tailscale, allowing your Firewalla to access your firewalla networks when you are away or, use it like a VPN Server to route all internet traffic through your Firewalal network. 

## Why Tailscale?
Firewalla comes with a no-subscription VPN which is amazing. Why do I need tailscale? 

Firealla has:
*   **[VPN Server](https://help.firewalla.com/hc/en-us/articles/115004274633-Firewalla-VPN-Server):** allows you to access devices on your Firewalla-network when you are away.
*   **[VPN Client](https://help.firewalla.com/hc/en-us/articles/360023379953-VPN-Client):** allows your Firealla to connect to another VPN server so your devices don't have to. Want to run your Apple TV through a VPN? just assign it to the VPN client.

So _why tailscale_? There are a many [possible answers](https://www.reddit.com/r/firewalla/comments/1l64s6w/why_is_firewalla_silent_about_tailscale/) to this.

Tailscale is appealing because it works even if your ISP doesn’t give you a public IP. Many ISPs now place users behind Carrier-Grade NAT (CGNAT), making traditional VPNs like Firewalla’s difficult or impossible to set up. Tailscale handles this automatically, so you can connect to your home network from anywhere, even without a public IP.

It also integrates seamlessly across all your devices. You don’t need to configure separate VPN clients or remember multiple setups—once a device joins your Tailscale network, it can securely connect to any other authorized device.

Finally, you don’t have to keep switching VPN software to connect different devices. Everything uses the same credentials and rules, making device-to-device access consistent and hassle-free.

**Bottom line:** Tailscale provides a unified, always-on private network that just works—no public IP, no complex VPN setup, and no juggling multiple clients.

Tailscale has a [free tier](https://tailscale.com/pricing) with some limits. Problem solved!

## ✨ Features of this script

*   **Interactive Installation:** A guided setup process that makes configuration easy.
*   **Automatic Subnet Detection:** The script automatically detects your local subnets (LAN and VLANs) and asks which ones you want to make accessible through Tailscale.
*   **Simple Exit Node Setup:** A simple yes/no prompt to configure your Firewalla as an exit node.
*   **Clean Uninstallation:** A dedicated script to remove all traces of the Tailscale Docker setup.
*   **Minimal Impact:** Designed to integrate seamlessly with Firewalla's existing Docker environment without interference.
*   **Persistent Operation:** Installs a start script (`/home/pi/.firewalla/config/post_main.d/tailscale-start.sh`) that ensures Tailscale automatically starts after reboots and Firewalla updates.


## Passthrough vs split 
GEMINI: Add a bit here explaining that the script currently assumes a split-tunnel approach but a full tunnel is possible the configuration may be added in future.) Merge text from above if it makes sense. 

## ⚠️ Important Notes

on Subnet Representation

* When configuring subnet routes, Firewalla typically displays network addresses with a host IP (e.g., `192.168.10.1/24`). However, Tailscale requires the network address to end in `.0` (e.g., `192.168.10.0/24`).

This installer script automatically handles this conversion for you. When it discovers available subnets and asks if you want to advertise them, it will present them in the Tailscale-compatible `.0` format. You should approve these subnets as presented by the script.

* Tailscale has a lot of options. Thos installer doesn't try to account for every possible configuration parameter. if there are requests, I might add in the future, but this will get you started.

* Only tested on Gold in Router mode. Should work on Purple too.

## 📝 Preparation

### Required
    *   **A Firewalla device (only tested on Gold series for now).** 
    *   **An active [Tailscale account](https://login.tailscale.com/start).**
    *   **A Tailscale Auth Key.** You can generate one from your Tailscale admin console under **Settings** -> **Auth keys**.

### Recommended
    *   In the Firewalla app, create a new LAN with a specific IP range. We suggest using a subnet with `100` as the third octet (e.g., `192.168.100.0/24`).
    *   It is okay to disable DHCP, mDNS, and SSDP on this new VLAN.
    *   This VLAN will be used to create rules in Firewalla to control Tailscale's access to the rest of your network. For example, you could allow just a device Group to be accessed by Tailscale using Firewalla's UI.

    Alternatively, if you prefer not to create a new tailscale VLAN, you can use existing LANs or VLANs. In this case, the script will present your existing subnets and allow you to advertise them. Any networks you choose will be directly accessible from tailscale so do this with caution. 

## 🚀 Installation

[SSH to your firewalla. ](https://help.firewalla.com/hc/en-us/articles/115004397274-How-to-access-Firewalla-using-SSH)
To install Tailscale on your Firewalla, SSH into your Firewalla device and run the following command:

```bash
# replace this URL
curl -sSL 'https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh' | sudo bash
```

The script is interactive and will guide you through the following steps:

1.  Enter your **Tailscale Auth Key:** You will be prompted to enter your auth key. [[tailscale docs](https://tailscale.com/kb/1085/auth-keys/)]
2.  Choose **Advertise Subnets:** The script will detect all the local subnets (LAN and VLANs) configured on your Firewalla. If you have created a dedicated VLAN with `.100.` in its third octet (e.g., `192.168.100.0/24`), the script will recommend this as the primary subnet to advertise. If you accept this, you may not need to advertise any other subnets. The script will then ask if you wish to advertise any other detected subnets.
3.  **Exit Node:** You will be asked if you want to use your Firewalla as an exit node. An exit node allows you to route all of your internet traffic through your Firewalla, no matter where you are. In simple terms, it makes your internet traffic appear to come from your Firewalla's IP address, just like a traditional VPN. This isn't needed if you just want to access your devices remotely. 

Based on your answers, the script will automatically create your `docker-compose.yml` file, pull the container image, and start Tailscale for you. It will persist reboots and firewalla updates but not if you flash your firewalla. 

### Advanced Users

The `install.sh` script includes the following flags for more controlled execution:

*   **Test Mode (`-t`):** Run the script in "dry run" mode to see which commands would be executed without actually making any changes. This is useful for testing and understanding what the script will do before you run it. This is only a test! 

    ```bash
    # replace URL
    curl -sSL https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh | sudo bash -s -- -t
    ```

*   **Confirm Mode (`-c`):** Run the script in confirm mode to be prompted for approval before each command is executed. This gives you fine-grained control over the installation process. If you elect not to do something, there's no guarantee things will work so use with great caution and only if you know what you are doing.

    ```bash
    # replace URL
    curl -sSL https://raw.githubusercontent.com/mbierman/firewalla-tailscale-docker/main/install.sh | sudo bash -s -- -c
    ```

### ➡️ Post-Installation Steps

After the installation script completes, you **must** perform the following steps in your Tailscale admin console:

1.  **Authorize Device:** Go to the [Machines page](https://login.tailscale.com/admin/machines) and authorize your newly added Firewalla device.
2.  **Enable Subnet Routes:** If you chose to advertise any subnets, you must enable them. Click the `...` menu next to your Firewalla device, select **Edit route settings...**, and enable the routes you want to use.
3.  **Enable Exit Node (if chosen):** If you chose to use your Firewalla as an exit node, you **must** enable it. In the [Machines page](https://login.tailscale.com/admin/machines), click the `...` menu next to your Firewalla device and select **Edit route settings...**. Then, enable the `Use as exit node` toggle.

Once enabled, you can select your Firewalla as an exit node from the Tailscale client on your other devices. For more information, see the [Tailscale documentation on exit nodes](https://tailscale.com/kb/1019/subnets#exit-nodes).

### ⚙️ Configure Tailscale Dashboard

1. To create an athorization key, go to [Tailscale's documentation on auth keys](https://tailscale.com/kb/1085/auth-keys/). and find Settings (1), Keys (2) , Generate Auth Key (3) 
<img src="assets/Key.jpg" alt="Find Keys" width="800"/>

2. Give a name for your firewalla (1), choose Reusable so it won't expire each time you start your docker and Gnerarte. 
<img src="assets/Key 2.jpg" alt="Create Key" width="400"/>

3. Run the script

   GEMENI Move the instructions here. 

<img src="assets/Approve.jpg" alt="Approve your Firewalla" width="800"/>

6. Approve the Route
<img src="assets/Routes.jpg" alt="Approve routes" width="400"/>

5. Check that you ad a name server for firewalla. Usually this matches the LAN for example, if you are adding 192.168.5.0/24, the DNS server would be 192.168.5.1 (1). Choose Split DMS (2) amd Override DNS server (3)
<img src="assets/DNS.jpg" alt="Configure DNS" width="800"/>


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

*   **Confirm Mode (`-c`):
    ```bash
    sudo /data/uninstall-tailscale-firewalla.sh -c
    ```

## 💡 How It Works

Magic. 

The installer script automates the process described in the [official Tailscale documentation for running in Docker](https://tailscale.com/kb/1282/docker). It detects your local networks and interactively helps you build the correct `--advertise-routes` and `--advertise-exit-node` arguments.

## 📚 References

*   [Tailscale: How to run Tailscale in Docker](https://tailscale.com/kb/1282/docker)
*   [Tailscale: Subnet routers and traffic relay nodes](https://tailscale.com/kb/1019/subnets)
*   [Reddit: Easy Tailscale integration via docker compose](https://www.reddit.com/r/firewalla/comments/1mlrtvi/easy-tailscale_integration_via_docker_compose/) (Credit to u/adrianmihalko for the original concept)

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

---
Made with 🔥 and ❤️  for the Firewalla Community! Not associated with or supported by Firewalla.
