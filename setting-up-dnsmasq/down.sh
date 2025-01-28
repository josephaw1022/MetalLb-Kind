#!/bin/bash

set -e

echo "Tearing down the simpler dnsmasq and systemd-resolved setup..."

# Remove dnsmasq configuration
if [ -f /etc/dnsmasq.conf ]; then
  echo "Removing dnsmasq configuration..."
  sudo rm -f /etc/dnsmasq.conf
fi

# Restore systemd-resolved DNSStubListener
if [ -f /etc/systemd/resolved.conf.d/noresolved.conf ]; then
  echo "Restoring systemd-resolved DNSStubListener..."
  sudo rm -f /etc/systemd/resolved.conf.d/noresolved.conf
fi

# Restore /etc/resolv.conf to systemd-resolved
if grep -q "127.0.0.1" /etc/resolv.conf; then
  echo "Restoring /etc/resolv.conf to systemd-resolved..."
  sudo rm -f /etc/resolv.conf
  sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
fi

# Restart services
echo "Stopping and disabling dnsmasq..."
sudo systemctl stop dnsmasq
sudo systemctl disable dnsmasq

echo "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

echo "Tear-down complete."
