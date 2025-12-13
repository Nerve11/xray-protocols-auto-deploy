# Xray VLESS+WS+TLS / XHTTP Auto-Installer 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A simple and powerful Bash script for fully automated installation and configuration of a VPN server based on **Xray** using the **VLESS** protocol.

Supports three installation modes:

- **VLESS + WS + TLS** on port **443** with masquerading as `google.com` (SNI/Host)
- **VLESS + XHTTP + TLS** on port **2053** with SNI/Host `google.com`
- **BOTH MODES** simultaneously (ports 443 and 2053, shared UUID)

The script focuses on providing **low latency** for online gaming, stable connections, and bypassing moderate to advanced internet blocking through modern Xray transports.

**Features:**

- ✨ **Fully Automatic:** The script handles everything from dependency installation to configuration generation and service restart.
- 🚀 **Speed & Gaming Optimized:**
  - VLESS protocol (lower overhead compared to VMess)
  - Choice between WebSocket and XHTTP in interactive menu at launch
  - Automatically enables **TCP BBR** (if supported by kernel) for improved throughput
- 🛡️ **Security & Blocking Circumvention:**
  - TLS with self-signed certificate
  - HTTPS traffic masquerading with `google.com` domain via SNI/Host
  - Built-in secure DNS (DoH from Cloudflare/Google/Quad9) inside Xray
- 💻 **Wide OS Support:**
  - Ubuntu 20.04+
  - Debian 10+
  - CentOS 7+ / AlmaLinux / Rocky Linux
- 🔑 **IP-based Connection:** No domain name required. Perfect for quick VPS deployment.
- ⚙️ **Simple Management:** Integration with `systemd` for Xray service management (status, restart, logs).
- 📱 **Convenient Output:** Generates ready-to-use **VLESS links** and **QR codes** for easy client import.

---

## Requirements

- Clean VPS (Virtual Private Server)
- Supported OS (Ubuntu 20.04+, Debian 10+, CentOS 7+ / AlmaLinux / Rocky Linux)
- SSH access to server with `root` privileges or user with `sudo`

---

## 🚀 Quick Start

1. Download the installation script:
   ```bash
   wget -O install-vless.sh \
     https://raw.githubusercontent.com/Nerve11/Auto-intall-Xray-VLESS-WS-TLS/main/install-vless.sh
   # or
   # curl -o install-vless.sh https://raw.githubusercontent.com/Nerve11/Auto-intall-Xray-VLESS-WS-TLS/main/install-vless.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x install-vless.sh
   ```

3. Run the script with sudo privileges:
   ```bash
   sudo ./install-vless.sh
   ```

4. In the interactive menu, select installation mode:
   - `1` – **VLESS + WS + TLS** on port **443**
   - `2` – **VLESS + XHTTP + TLS** on port **2053**
   - `3` – **BOTH MODES** (ports 443 and 2053, shared UUID)

5. Wait for completion! The script will execute all steps and display summary information including VLESS link(s) and WS path (for WebSocket mode).

---

## 🎉 After Installation

Upon completion, the script outputs:

- **VPN parameters:** Server IP address, port(s), UUID, mode (WS/XHTTP/both), WS path (for WS mode)
- **Ready-to-use VLESS link(s):** Can be copied entirely and imported into client
- **QR code information:** File(s) `vless_ws_qr.png` and/or `vless_xhttp_qr.png` saved in the home directory of the user who ran `sudo` (usually `/root/` or `/home/username/`)

---

## 📱 Client Configuration

1. **Import configuration:**
   - Use VLESS link or QR code in your client (v2rayNG, v2rayN, Nekoray, Shadowrocket, etc.)

2. **Allow insecure connection:**
   - Enable one of these options in TLS/Security section:
     - `Allow Insecure`
     - `skip certificate verification`
     - `tlsAllowInsecure=1`
   - This is required because a self-signed certificate is used.

3. **Verify SNI / Host:**
   - For both modes (WS and XHTTP) **SNI/Host must be `google.com`**
   - Server address in client profile should be your VPS IP (or domain if you configure one)

4. **Transport parameters:**

| Mode                | Port | type   | path            | security | sni/Host   |
|---------------------|------|--------|-----------------|----------|-----------|
| VLESS + WS + TLS    | 443  | ws     | `/RANDOM_PATH`  | tls      | google.com|
| VLESS + XHTTP + TLS | 2053 | xhttp  | (no path)       | tls      | google.com|

- For XHTTP, clients must support the XHTTP transport (modern versions of v2rayNG/v2rayN/Nekoray)

---

## 🔧 Xray Server Management

Standard `systemctl` commands:

- Check status: `sudo systemctl status xray`
- Restart: `sudo systemctl restart xray`
- Stop: `sudo systemctl stop xray`
- Start: `sudo systemctl start xray`
- Enable autostart: `sudo systemctl enable xray`
- Disable autostart: `sudo systemctl disable xray`

**View logs:**

- Errors: `sudo tail -f /var/log/xray/error.log`
- Access logs (if enabled): `sudo tail -f /var/log/xray/access.log`
- Full service log: `sudo journalctl -u xray -f --no-pager`

---

## ⚙️ Customization

- **Ports:**
  - Default: 443 for WS, 2053 for XHTTP
  - Can be changed at the beginning of the script (variables `VLESS_PORT_WS` and `VLESS_PORT_XHTTP`) before running
- **Additional optimization:**
  - For fine-tuning buffers and timeouts, edit `/usr/local/etc/xray/config.json` after installation
  - You can add a `"policy"` section and configure `bufferSize` and other parameters. Requires Xray restart and testing.

---

## 🔍 Troubleshooting

- **Xray service won't start:**
  - `sudo journalctl -u xray -n 50 --no-pager`
  - Check if port is occupied: `sudo ss -tlpn | grep <PORT>`
  - Validate config: `sudo /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json`

- **Low speed:**
  - Ensure BBR is enabled: `sysctl net.ipv4.tcp_congestion_control` should show `bbr`
  - Check server speed itself (`speedtest-cli`)
  - Check route and packet loss (`mtr` / `WinMTR`)
  - Monitor CPU load (`htop`)

- **Client won't connect:**
  - Verify `Allow Insecure` is enabled
  - Ensure **SNI/Host = google.com**
  - Check firewall rules (UFW / firewalld) on port 443 or 2053 depending on mode

---

## 🔒 Security

- Uses self-signed certificate, so the client trusts the certificate directly rather than through CA chain
- For maximum "natural" HTTPS traffic, advanced scenarios recommend using your own domain and/or more complex configurations (REALITY, CDN, etc.), but this script focuses on quick deployment and masquerading as `google.com` via SNI

---

## 📜 License

Project is licensed under MIT. See `LICENSE` file.
