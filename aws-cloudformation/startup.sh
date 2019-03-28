#!/bin/bash

# This is a startup script for a Docksal Sandbox server in GCP.
# It installs and configures Docksal on a bare Ubuntu machine (tested with Ubuntu 18.04 Minimal).
#
# The startup script log can be views via "gcloud compute ssh vm-sandbox-test -- tail -f /var/log/syslog"

set -x  # Print commands
set -e  # Fail on errors

# Persistent disk settings
DISK_LABEL="data-volume"
MOUNT_POINT="/data"
BUILD_USER="build-agent"
BUILD_USER_UID="1100"
BUILD_USER_HOME="/home/${BUILD_USER}"
DATA_BUILD_USER_HOME="${MOUNT_POINT}${BUILD_USER_HOME}"
DOCKSAL_VERSION="master"
PROJECT_INACTIVITY_TIMEOUT="0.5h"
PROJECT_DANGLING_TIMEOUT="168h"
PROJECTS_ROOT="${BUILD_USER_HOME}/builds"

mount_part()
{
    DATA_DISK=$1
    # mark disk with label
    tune2fs -L ${DISK_LABEL} ${DATA_DISK} >/dev/null 2>&1
    # Mount the data disk
    mkdir -p ${MOUNT_POINT}
    cp /etc/fstab /etc/fstab.backup
    # Write disk mount to /etc/fstab (so that it persists on reboots)
    # Equivalent of `mount /dev/sdb /mnt/data`
    echo "LABEL=${DISK_LABEL} ${MOUNT_POINT}  ext4  defaults,nofail  0 2" | tee -a /etc/fstab
    mount -a
}

create_fs()
{
    # creating ext4 fs and add label
    DATA_DISK=$1
    mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard ${DATA_DISK} -L ${DISK_LABEL} >/dev/null 2>&1
}

get_part_list()
{
    # get disk partitions info.
    # the result will contain strings: NAME="/dev/nvme1n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT="" NAME="/dev/nvme0n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT=""
    # in our case will be only one string
    DATA_DISK=$1
    blockdev --rereadpt ${DATA_DISK}
    lsblk -p -n -P -o NAME,TYPE,FSTYPE,LABEL,MOUNTPOINT ${DATA_DISK} | grep part | sed 's/ /;/g'
}

create_part()
{
    # create msdos partition table and create primary partition used 100% disk size
    DATA_DISK=$1
    /sbin/parted ${DATA_DISK} -s mklabel msdos
    /sbin/parted ${DATA_DISK} -s -a optimal mkpart primary 0% 100%
}

# Create build-agent user with no-password sudo access
# Forcing the uid to avoid race conditions with GCP creating project level users at the same time.
# (Otherwise, we may run into something like "useradd: UID 1001 is not unique")
if [[ "$(id -u ${BUILD_USER})" != "${BUILD_USER_UID}" ]]; then
	adduser --disabled-password --gecos "" --uid ${BUILD_USER_UID} ${BUILD_USER}
	usermod -aG sudo ${BUILD_USER}
	echo "${BUILD_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/101-${BUILD_USER}
fi

# Wait for data volume attachment (necessary with AWS EBS)
wait_count=0
wait_max_attempts=12
while true
do
    let "wait_count+=1"
    # additional data disk is considered attached when number of disk attached to instance more than 1
    [[ "$(lsblk -p -n -o NAME,TYPE | grep disk | wc -l)" > 1 ]] && break
    (( ${wait_count} > ${wait_max_attempts} )) && break
    echo "Waiting for EBS volume to attach (${wait_count})..."
    sleep 5
done

# find additional data disk, format it and mount
for disk in $(lsblk -d -p -n -o NAME,TYPE | grep disk | cut -d' ' -f1)
do
    # partitioning disk if disk is clean
    [[ $(get_part_list "${disk}") == "" ]] && { echo "Disk ${disk} is clean! Creating partition..."; create_part "${disk}"; }
    eval $(echo $(get_part_list "${disk}"))
    # skip disk if his partition is mounted
    [[ "$MOUNTPOINT" != "" ]] && { echo "Disk $disk have partition $NAME, and it already mounted! Skipping..."; continue; }
    # mount disk partition if ext4 fs found, but not mounted (volume was added from another instance)
    [[ "$FSTYPE" == "ext4" ]] && { echo "Disk $disk have partition $NAME with FS, but not mounted! Mounting..."; mount_part "$NAME"; continue; }
    # create fs and mount when we already have partition, but fs not created yet
    echo "Disk $disk have partition $NAME, but does not have FS! Creating FS and mounting..."
    create_fs "${NAME}"
    mount_part "${NAME}"
done

if [ -d $MOUNT_POINT ]
then
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
