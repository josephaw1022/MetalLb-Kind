#!/bin/bash

set -e

echo "Setting up dnsmasq as the primary DNS resolver (simpler method)..."

# Install dnsmasq
echo "Installing dnsmasq..."
sudo dnf install -y dnsmasq

# Configure dnsmasq
echo "Configuring dnsmasq..."
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
bind-interfaces
listen-address=127.0.0.1

# Prevent dnsmasq from reading /etc/resolv.conf
no-resolv

# Upstream DNS servers
server=8.8.8.8
server=8.8.4.4

# Directory for additional configurations
conf-dir=/etc/dnsmasq.d
EOF

# Disable systemd-resolved DNSStubListener
echo "Disabling systemd-resolved's DNSStubListener..."
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/noresolved.conf > /dev/null <<EOF
[Resolve]
DNSStubListener=no
EOF

# Restart services
echo "Restarting dnsmasq..."
sudo systemctl enable dnsmasq --now
echo "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

# Point resolv.conf to dnsmasq
echo "Configuring /etc/resolv.conf to use dnsmasq..."
sudo rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null

echo "Setup complete. dnsmasq is now managing DNS resolution."
