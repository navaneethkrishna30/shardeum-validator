#!/usr/bin/env bash

set -e
USE_SUDO=0

# Set default base directory
NODEHOME=$(realpath "${HOME}/shardeum")
mkdir -p "$NODEHOME"

echo "Base directory set to: $NODEHOME"

command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is not installed on this machine but is required to run the shardeum validator. Please install docker before continuing."; exit 1; }

docker-safe() {
  if ! command -v docker &>/dev/null; then
    echo "Docker is not installed on this machine"
    exit 1
  fi
  if ! docker "$@"; then
    echo "Trying again with sudo..." >&2
    USE_SUDO=1
    sudo docker "$@"
  fi
}

if [[ $(docker-safe info 2>&1) == *"Cannot connect to the Docker daemon"* ]]; then
    echo "Docker daemon is not running, please start the Docker daemon and try again"
    exit 1
else
    echo "Docker daemon is running"
fi

# Default port values
DASHPORT=8080
SHMEXT=9001
SHMINT=10001
RUNDASHBOARD=y

# Get external and internal IP
get_external_ip() {
  external_ip=$(curl -s https://api.ipify.org || curl -s http://checkip.dyndns.org | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" || curl -s http://ipecho.net/plain || curl -s https://icanhazip.com/ || curl --header "Host: icanhazip.com" -s 104.18.114.97)
  echo "${external_ip:-localhost}"
}

EXTERNALIP=$(get_external_ip)
INTERNALIP=$EXTERNALIP
SERVERIP=$EXTERNALIP
LOCALLANIP=$INTERNALIP

# Remove old containers
OLD_IMAGE="ghcr.io/shardeum/server:latest"
CONTAINER_IDS=$(docker-safe ps -aq --filter "ancestor=$OLD_IMAGE")
if [ -n "$CONTAINER_IDS" ]; then
  docker-safe stop $CONTAINER_IDS 1>/dev/null
  docker-safe rm $CONTAINER_IDS 1>/dev/null
  echo "Old containers removed."
fi

# Stop and remove previous validator instance
if docker-safe ps -a --filter "name=shardeum-validator" --format "{{.Names}}" | grep -q "^shardeum-validator$"; then
    echo "Stopping and removing previous instance of shardeum-validator"
    docker-safe stop shardeum-validator 2>/dev/null
    docker-safe rm shardeum-validator 2>/dev/null
fi

target_uid=1000
owner_uid=$(stat -c '%u' "$NODEHOME")
if [ "$owner_uid" -ne "$target_uid" ]; then
  sudo chown "$target_uid" "$NODEHOME" || { echo "Failed to change ownership of $NODEHOME"; exit 1; }
fi

echo "Downloading the Shardeum Validator image and starting the container"
docker-safe pull ghcr.io/shardeum/shardeum-validator:latest 
docker-safe run \
    --name shardeum-validator \
    -p ${DASHPORT}:${DASHPORT} \
    -p ${SHMEXT}:${SHMEXT} \
    -p ${SHMINT}:${SHMINT} \
    -e RUNDASHBOARD=${RUNDASHBOARD} \
    -e DASHPORT=${DASHPORT} \
    -e EXT_IP=${EXTERNALIP} \
    -e INT_IP=${INTERNALIP} \
    -e SERVERIP=${SERVERIP} \
    -e LOCALLANIP=${LOCALLANIP} \
    -e SHMEXT=${SHMEXT} \
    -e SHMINT=${SHMINT} \
    -v ${NODEHOME}:/home/node/config \
    --restart=always \
    --detach \
    ghcr.io/shardeum/shardeum-validator 1>/dev/null

echo "Shardeum Validator starting. Waiting for the container to be available..."

PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' </dev/urandom | fold -w 16 | head -n 1)

docker-safe exec shardeum-validator operator-cli gui set password "$PASSWORD"

echo "$PASSWORD" > /root/password.txt

DASHBOARD_URL="https://${EXTERNALIP}:${DASHPORT}/"
echo "$DASHBOARD_URL" > /root/dashboard_url.txt
echo "Shardeum Validator is now running."
