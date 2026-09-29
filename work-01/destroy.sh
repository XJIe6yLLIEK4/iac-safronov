#!/usr/bin/env bash

set -euo pipefail

readonly PREFIX="safronov-08"
readonly NETWORK_NAME="${PREFIX}-net"
readonly SUBNET_NAME="${PREFIX}-subnet"

delete_instance_if_exists() {
  local name="$1"

  if yc compute instance get "${name}" >/dev/null 2>&1; then
    yc compute instance delete "${name}"
  fi
}

delete_instance_if_exists "${PREFIX}-app-1"
delete_instance_if_exists "${PREFIX}-app-2"

if yc vpc subnet get "${SUBNET_NAME}" >/dev/null 2>&1; then
  yc vpc subnet delete "${SUBNET_NAME}"
fi

if yc vpc network get "${NETWORK_NAME}" >/dev/null 2>&1; then
  yc vpc network delete "${NETWORK_NAME}"
fi
