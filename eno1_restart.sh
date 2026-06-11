#!/bin/bash

INTERFACE="${1:-eno1}"

if ! ip link show "$INTERFACE" &>/dev/null; then
    echo "Error: Interface '$INTERFACE' not found."
    exit 1
fi

echo "Bouncing interface: $INTERFACE"
sudo ip link set "$INTERFACE" down && echo "  [down]" || { echo "Failed to bring down $INTERFACE"; exit 1; }
sleep 1
sudo ip link set "$INTERFACE" up   && echo "  [up]"   || { echo "Failed to bring up $INTERFACE";   exit 1; }

echo "Done. Current state:"
ip link show "$INTERFACE"