#!/bin/bash

# Settings
xfreerdp --version
read -p 'User: ' user
read -p 'Host: ' host
size="1920x1080"

# Connect to RDP Server
xfreerdp /u:$user /v:$host /size:$size /bpp:32 +clipboard +fonts /gdi:hw /rfx \
    /rfx-mode:video +window-drag
