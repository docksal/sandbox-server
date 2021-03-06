#!/bin/bash

# This is a startup script for a Docksal Sandbox server in GCP.
# It installs and configures Docksal on a bare Ubuntu machine (tested with Ubuntu 20.04 Minimal).
#
# The startup script log can be views via "gcloud compute ssh vm-sandbox-test -- tail -f /var/log/syslog"

set -x  # Print commands
set -e  # Fail on errors

# Helper function for getting metadata.
get_metadata() {
  curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1 -H "Metadata-Flavor: Google" 2>/dev/null
}

# Persistent disk settings
DATA_DISK="/dev/sdb"
MOUNT_POINT="/data"
BUILD_USER="build-agent"
BUILD_USER_UID="1100"
BUILD_USER_HOME="/home/${BUILD_USER}"
DATA_BUILD_USER_HOME="${MOUNT_POINT}${BUILD_USER_HOME}"
DOCKSAL_VERSION="$(get_metadata docksalVersion)"
PROJECT_INACTIVITY_TIMEOUT="0.5h"
PROJECT_DANGLING_TIMEOUT="168h"
PROJECTS_ROOT="${BUILD_USER_HOME}/builds"

set_docksal_dns_domain() {
  local base_metadata="http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
  local dns_attr="DOCKSAL_DNS_DOMAIN"
  local flavor_header="Metadata-Flavor: Google"
  local metadata=$(curl "$base_metadata" -H "$flavor_header" 2>/dev/null)
  if [[ "$metadata" == *"$dns_attr"* ]] ; then
    # We assume that if the attribute is present in the metadata directory then
    # it has an accompanying value.
    local dns_attr_value=$(curl "${base_metadata}${dns_attr}" -H "$flavor_header" 2>/dev/null)
    sed -i "/^$dns_attr/d" "/home/$BUILD_USER/.docksal/docksal.env"
    echo "$dns_attr=\"$dns_attr_value\"" | tee -a "/home/$BUILD_USER/.docksal/docksal.env" >/dev/null
  fi
}

apt update
apt install -y vim

# Mount the persistent data disk if it was attached
if lsblk ${DATA_DISK} &>/dev/null; then
  echo "Using persistent disk: ${DATA_DISK} for data storage: ${MOUNT_POINT}"

  # Format the disk if necessary
  if [[ $(lsblk -f ${DATA_DISK}) != *ext4* ]]; then
    mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard ${DATA_DISK}
  fi

  # Mount the data disk
  mkdir -p ${MOUNT_POINT}
  cp /etc/fstab /etc/fstab.backup
  # Write disk mount to /etc/fstab (so that it persists on reboots)
  # Equivalent of `mount /dev/sdb /mnt/data`
  echo "${DATA_DISK}  ${MOUNT_POINT}  ext4  defaults,nofail  0 2" | tee -a /etc/fstab
  mount -a

  # Move BUILD_USER_HOME to the data disk
  # E.g. /home/build-agent => /mnt/data/home/build-agent
  if [[ ! -d ${DATA_BUILD_USER_HOME} ]]; then
    mkdir -p $(dirname ${DATA_BUILD_USER_HOME})
    mv ${BUILD_USER_HOME} $(dirname ${DATA_BUILD_USER_HOME})
  else
    rm -rf ${BUILD_USER_HOME}
  fi
  ln -s ${DATA_BUILD_USER_HOME} ${BUILD_USER_HOME}

  # Symlink /var/lib/docker (should not yet exist when this script runs) to the data volume
  mkdir -p ${MOUNT_POINT}/var/lib/docker
  ln -s ${MOUNT_POINT}/var/lib/docker /var/lib/docker
else
  echo "WARNING: data volume not found. Using instance-only storage"
fi

# Create the projects/builds directory
mkdir -p ${PROJECTS_ROOT}

# SSH settings: ensure ~/.ssh exists for the build user
mkdir -p ${BUILD_USER_HOME}/.ssh

# SSH settings: authorized_keys
# If ~/.ssh/authorized_keys does not exist for the build user, reuse the one from the default user account (ubuntu)
if [[ ! -f "${BUILD_USER_HOME}/.ssh/authorized_keys" ]]; then
  cp "/home/ubuntu/.ssh/authorized_keys" "${BUILD_USER_HOME}/.ssh/authorized_keys"
  chown ${BUILD_USER}:${BUILD_USER} "${BUILD_USER_HOME}/.ssh/authorized_keys"
fi

# SSH settings: disable the host key check
if [[ ! -f "${BUILD_USER_HOME}/.ssh/config" ]]; then
  tee "${BUILD_USER_HOME}/.ssh/config" <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  LogLevel ERROR
EOF
  chmod 600 "${BUILD_USER_HOME}/.ssh/config"
fi

# Sandbox settings (set these before installing Docksal)
# Note: do nothing if docksal.env exists from a previos installation (persistent data disk)
if [[ ! -f ${BUILD_USER_HOME}/.docksal/docksal.env ]]; then
  mkdir -p ${BUILD_USER_HOME}/.docksal
  tee ${BUILD_USER_HOME}/.docksal/docksal.env <<EOF
CI=true
PROJECT_INACTIVITY_TIMEOUT="${PROJECT_INACTIVITY_TIMEOUT}"
PROJECT_DANGLING_TIMEOUT="${PROJECT_DANGLING_TIMEOUT}"
PROJECTS_ROOT="${PROJECTS_ROOT}"
EOF
  # Fix permissions
  #chown ${BUILD_USER}:${BUILD_USER} ${BUILD_USER_HOME}/.docksal/docksal.env
fi

# Fix permissions, since we are running as root here
# Trailing slash in necessary here, since BUILD_USER_HOME is a symlink
chown -R ${BUILD_USER}:${BUILD_USER} "${BUILD_USER_HOME}/"

# Unlock updates
# Necessary with existing installations (persistent data disk)
sed -i '/DOCKSAL_LOCK_UPDATES/d' "${BUILD_USER_HOME}/.docksal/docksal.env" || true

# Install/update Docksal and dependencies
su - ${BUILD_USER} -c "curl -fsSL https://get.docksal.io | DOCKSAL_VERSION=${DOCKSAL_VERSION} bash"

# Lock updates (protect against unintentional updates in builds)
echo "DOCKSAL_LOCK_UPDATES=1" | tee -a "${BUILD_USER_HOME}/.docksal/docksal.env"

set_docksal_dns_domain

su - ${BUILD_USER} -c fin system start
