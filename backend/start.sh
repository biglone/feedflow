#!/bin/bash

# FeedFlow Backend Startup Script
# Enables proxy for Google API access

# Enable proxy
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

echo "Proxy enabled: $http_proxy"

# Start backend
cd "$(dirname "$0")"
npm run dev
