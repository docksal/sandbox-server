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

##########
# Functions begin
reread_device()
{
    DEVICE=$1
    #hdparm -z ${DEVICE} >>/var/log/device.log 2>&1 || true
    #file -s ${DEVICE} >>/var/log/device.log 2>&1 || true
    partprobe ${DEVICE} >>/var/log/device.log 2>&1 || true
    #blockdev --rereadpt -v ${DEVICE} >>/var/log/device.log 2>&1 || true
    #fdisk -l ${DEVICE} >>/var/log/device.log 2>&1 || true
}

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

get_disk_info()
{
    # get disk/partitions info.
    # the result will contain strings: NAME="/dev/nvme1n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT="" NAME="/dev/nvme0n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT=""
    DATA_DISK=$1
    reread_device "$DATA_DISK"
    device_list="$(lsblk -p -n -P -o NAME,TYPE,FSTYPE,LABEL,MOUNTPOINT ${DATA_DISK} 2>&1 | sed 's/ /;/g')"
    while read device_info
    do
      eval ${device_info}
      # exit if device already mounted
      [[ ${MOUNTPOINT} != "" ]] && return
      # exit if device has ext4 fs
      [[ ${FSTYPE} == "ext4" ]] && return
    done <<< ${device_list}
    # if not found ext4 fs return empty data for creating new fs
    NAME=""; TYPE=""; FSTYPE=""; LABEL=""; MOUNTPOINT=""
}

create_part()
{
    # create msdos partition table and create primary partition used 100% disk size
    DATA_DISK=$1
    /sbin/parted ${DATA_DISK} -s mklabel msdos
}

##########
# Functions end

apt-get -y update
apt-get -y install awscli

export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export STACK_ID=$(aws ec2 describe-instances --instance-id ${INSTANCE_ID} --query 'Reservations[*].Instances[*].Tags[?Key==`StackId`].Value' --output text)
export EIP=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`IPAddress`].OutputValue' --output text)
export VOLUME_ID=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`PersistentVolume`].OutputValue' --output text)
export GITHUB_TOKEN=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`GitHubToken`].OutputValue' --output text)
export GITHUB_ORG_NAME=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`GitHubOrgName`].OutputValue' --output text)
export GITHUB_TEAM_SLUG=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`GitHubTeamSlug`].OutputValue' --output text)
export LETSENCRYPT_DOMAIN=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`LetsEncryptDomain`].OutputValue' --output text)
export LETSENCRYPT_CONFIG=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`LetsEncryptConfig`].OutputValue' --output text)

# attach elastic ip
[[ "${EIP}" != "" ]] && aws ec2 associate-address --instance-id ${INSTANCE_ID} --public-ip ${EIP}

# attach volume if exist
if [[ "${VOLUME_ID}" != "" ]]
then
    # Wait for EBS volume "available" status before attaching.
    # When updating a spot stack, the volume may be in use by the previous instance which has not yet been terminated.
    wait_count=0
    wait_max_attempts=30
    while true
    do
        let "wait_count+=1"
        # Check volume status. Non-empty output means volume is available and we can proceed.
        result=$(aws ec2 describe-volumes --volume-ids ${VOLUME_ID} --filters "Name=status,Values=available" --output text)
        [[ "${result}" != "" ]] && break

        # Fail if reached maximum attempts
        if (( ${wait_count} > ${wait_max_attempts} )); then
            echo "ERROR: Timed out waiting for EBS volume to be available."
            exit 1
        fi

        echo "Waiting for EBS volume to become available (${wait_count})..."
        sleep 10
    done

    # Attache the EBS volume to the instance
    aws ec2 attach-volume --volume-id ${VOLUME_ID} --instance-id ${INSTANCE_ID} --device /dev/sdp || true

    # Wait for data volume attachment to complete
    wait_count=0
    wait_max_attempts=6
    while true
    do
        let "wait_count+=1"
        # Consider additional data disk attached when number of disk attached to instance is > 1
        [[ "$(lsblk -p -n -o NAME,TYPE | grep disk | wc -l)" > 1 ]] && break

        # Fail if reached maximum attempts
        if (( ${wait_count} > ${wait_max_attempts} )); then
            echo "ERROR: Timed out waiting for EBS volume to attach."
            exit 1
        fi

        echo "Waiting for EBS volume to attach (${wait_count})..."
        sleep 10
    done

    # find additional data disk, format it and mount
    for disk in $(lsblk -d -p -n -o NAME,TYPE | grep disk | cut -d' ' -f1)
    do
        # get partition info
        get_disk_info "${disk}"
        [[ "$MOUNTPOINT" != "" ]] && { echo "Disk $NAME already mounted! Skipping..."; continue; }
        [[ "$FSTYPE" == "ext4" ]] && { echo "Disk $NAME have ext4 filesystem but not mounted! Mounting..."; mount_part "$NAME"; continue; }
        echo "Disk ${disk} is clean! Creating partition..."
        wipefs -fa ${disk} >/dev/null
        create_part "${disk}"
        create_fs "${disk}"
        mount_part "${disk}"
    done
fi

# Create build-agent user with no-password sudo access
# Forcing the uid to avoid race conditions with GCP creating project level users at the same time.
# (Otherwise, we may run into something like "useradd: UID 1001 is not unique")
if [[ "$(id -u ${BUILD_USER})" != "${BUILD_USER_UID}" ]]; then
    adduser --disabled-password --gecos "" --uid ${BUILD_USER_UID} ${BUILD_USER}
    usermod -aG sudo ${BUILD_USER}
    echo "${BUILD_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/101-${BUILD_USER}
fi

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

if [[ "${GITHUB_TOKEN}" != "" ]] && [[ "${GITHUB_ORG_NAME}" != "" ]] && [[ "${GITHUB_TEAM_SLUG}" != "" ]]
then
    BACKUP_SSH_PUBLIC_KEY="$(curl -s http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key)"
    # TODO: move ssh-rake script to separate repo
    curl -s https://raw.githubusercontent.com/docksal/sandbox-server/develop/aws-cloudformation/scripts/ssh-rake -o /usr/local/bin/ssh-rake
    sed -i "s|^GITHUB_TOKEN=\".*\"|GITHUB_TOKEN=\"${GITHUB_TOKEN}\"|" /usr/local/bin/ssh-rake
    sed -i "s|^GITHUB_ORG_NAME=\".*\"|GITHUB_ORG_NAME=\"${GITHUB_ORG_NAME}\"|" /usr/local/bin/ssh-rake
    sed -i "s|^GITHUB_TEAM_SLUG=\".*\"|GITHUB_TEAM_SLUG=\"${GITHUB_TEAM_SLUG}\"|" /usr/local/bin/ssh-rake
    sed -i "s|^BACKUP_SSH_PUBLIC_KEY=\".*\"|BACKUP_SSH_PUBLIC_KEY=\"${BACKUP_SSH_PUBLIC_KEY}\"|g" /usr/local/bin/ssh-rake
    chmod +x /usr/local/bin/ssh-rake
    /usr/local/bin/ssh-rake install
fi

if [[ "${LETSENCRYPT_DOMAIN}" != "" ]]
then
    ACMESH_CONTAINER="docksal-acme.sh"
    ACMESH_PATH="${BUILD_USER_HOME}/letsencrypt/acme.sh/data"
    CERTOUT_PATH="${BUILD_USER_HOME}/.docksal/certs"
    DSP="${DSP:-dns_aws}"

    tmp=$(mktemp)
    printenv >${tmp}
    eval "export ${LETSENCRYPT_CONFIG}"
    printenv | diff -u "${tmp}" - | grep -E "^\+\w+" | sed 's/^+//' >env.file
    
    docker rm -vf ${ACMESH_CONTAINER} 2>/dev/null || true
    docker run -d --restart always \
        --env-file env.file \
        --name ${ACMESH_CONTAINER} \
        -v ${CERTOUT_PATH}:/out \
        neilpang/acme.sh daemon

    rm -f "${tmp}" env.file

    docker exec ${ACMESH_CONTAINER} \
        --issue \
        --keylength 4096 \
        --dns ${DSP} \
        --domain "${LETSENCRYPT_DOMAIN}" \
        --domain "*.${LETSENCRYPT_DOMAIN}" \
        --fullchain-file /out/${LETSENCRYPT_DOMAIN}.crt \
        --key-file /out/${LETSENCRYPT_DOMAIN}.key \
        --log /proc/1/fd/1

    if [[ -f ${CERTOUT_PATH}/${LETSENCRYPT_DOMAIN}.key ]] && [[ -f ${CERTOUT_PATH}/${LETSENCRYPT_DOMAIN}.crt ]]
    then
        sed -i '/DOCKSAL_VHOST_PROXY_DEFAULT_CERT/d' "${BUILD_USER_HOME}/.docksal/docksal.env" || true
        echo DOCKSAL_VHOST_PROXY_DEFAULT_CERT=\"${LETSENCRYPT_DOMAIN}\" | tee -a "${BUILD_USER_HOME}/.docksal/docksal.env"
        chown -R ${BUILD_USER}:${BUILD_USER} "${BUILD_USER_HOME}/"
        fin system reset
    fi
fi

