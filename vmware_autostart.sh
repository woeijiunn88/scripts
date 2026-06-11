#!/bin/bash

# Settings
/opt/vmware-autostart/bin/autostart start
sudo ip link set eno1 down && sudo ip link set eno1 up
# To run above command without requiring a password, you need to configure sudoers:
# echo "woeijiunn88 ALL=(ALL) NOPASSWD: /sbin/ip link set eno1 down, /sbin/ip link set eno1 up" | sudo tee -a /etc/sudoers
vmware-tray
