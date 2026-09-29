#!/usr/bin/env bash

set -euo pipefail

readonly PREFIX="safronov-08"
readonly ZONE="ru-central1-b"
readonly CIDR="10.18.1.0/24"
readonly DISK_SIZE="20"
readonly IMAGE_FAMILY="ubuntu-2204-lts"
readonly APP_PORT="8024"
readonly PAGE_WORD="labwork"

readonly NETWORK_NAME="${PREFIX}-net"
readonly SUBNET_NAME="${PREFIX}-subnet"
readonly SSH_KEY="${HOME}/.ssh/id_ed25519.pub"

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH public key not found: ${SSH_KEY}" >&2
  exit 1
fi

yc vpc network create \
  --name "${NETWORK_NAME}"

yc vpc subnet create \
  --name "${SUBNET_NAME}" \
  --network-name "${NETWORK_NAME}" \
  --zone "${ZONE}" \
  --range "${CIDR}"

create_instance() {
  local name="$1"

  yc compute instance create \
    --name "${name}" \
    --zone "${ZONE}" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="${IMAGE_FAMILY}",type=network-hdd,size="${DISK_SIZE}" \
    --network-interface subnet-name="${SUBNET_NAME}",nat-ip-version=ipv4 \
    --hostname "${name}" \
    --ssh-key "${SSH_KEY}" \
    --labels created-by=cli
}

create_instance "${PREFIX}-app-1"
create_instance "${PREFIX}-app-2"
