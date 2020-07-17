Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

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
PROJECT_INACTIVITY_TIMEOUT="0.5h"
PROJECT_DANGLING_TIMEOUT="168h"
PROJECTS_ROOT="${BUILD_USER_HOME}/builds"
ATTACH_VOLUME_AS="/dev/sdp"

##########
# Functions begin
move_to_data()
{
    local SRC_DIR=$1
    local DST_DIR=$2
    if [[ ! -d ${DST_DIR}${SRC_DIR} ]]; then
        mkdir -p ${DST_DIR}${SRC_DIR}
        [[ -d ${SRC_DIR} ]] && [[ ! -L ${SRC_DIR} ]] && mv ${SRC_DIR} ${DST_DIR}$(dirname ${SRC_DIR})
    fi
    rm -rf ${SRC_DIR} && ln -s ${DST_DIR}${SRC_DIR} ${SRC_DIR}
}

wait_volume_status()
{
    # Wait for EBS volume status.
    local volume=$1
    local status=$2
    local wait_count=0
    local wait_max_attempts=30
    while true
    do
        let "wait_count+=1"
        # Check volume status. Non-empty output means volume in required status and we can proceed.
        [[ "$(aws ec2 describe-volumes --volume-ids ${volume} --filters "Name=status,Values=${status}" --output text)" != "" ]] && break

        # Fail if reached maximum attempts
        if (( ${wait_count} > ${wait_max_attempts} )); then
            echo "ERROR: Timed out waiting for EBS volume to be ${status}."
            exit 1
        fi

        echo "Waiting for EBS volume to become available (${wait_count})..."
        sleep 10
    done
}

reread_device()
{
    DEVICE=$1
    hdparm -z ${DEVICE} || true
    file -s ${DEVICE} || true
    partprobe ${DEVICE} || true
    blockdev --rereadpt -v ${DEVICE} || true
    fdisk -l ${DEVICE} || true
}

mount_part()
{
    DATA_DISK=$1
    # mark disk with label
    tune2fs -L ${DISK_LABEL} ${DATA_DISK}
    # Mount the data disk
    mkdir -p ${MOUNT_POINT}
    mount ${DATA_DISK} ${MOUNT_POINT}
}

create_fs()
{
    # creating ext4 fs and add label
    DATA_DISK=$1
    mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard ${DATA_DISK} -L ${DISK_LABEL}
}

get_disk_info()
{
    # get disk/partitions info.
    # the result will contain strings: NAME="/dev/nvme1n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT="" NAME="/dev/nvme0n1";TYPE="disk";FSTYPE="";LABEL="";MOUNTPOINT=""
    DATA_DISK=$1
    reread_device "$DATA_DISK"
    while read device_info
    do
      eval ${device_info}
      # exit if device already mounted
      [[ ${MOUNTPOINT} != "" ]] && return
      # exit if device has ext4 fs
      [[ ${FSTYPE} == "ext4" ]] && return
    done <<< "$(lsblk -p -n -P -o NAME,TYPE,FSTYPE,LABEL,MOUNTPOINT ${DATA_DISK} 2>&1 | sed 's/ /;/g')"
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

# install aws cli if instance just created
if [[ ! -f /root/stack_last_update ]]
then
    apt-get -y update
    apt-get -y install awscli
else
    old_stack_md5sum="$(cat /root/stack_last_update)"
fi

# read necessary variables
export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export STACK_ID=$(aws ec2 describe-instances --instance-id ${INSTANCE_ID} --query 'Reservations[*].Instances[*].Tags[?Key==`StackId`].Value' --output text)
export ATTACHED_IP=$(aws ec2 describe-instances --instance-id ${INSTANCE_ID} --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
export ATTACHED_VOLUME=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=${INSTANCE_ID} Name=attachment.device,Values=${ATTACH_VOLUME_AS} --query 'Volumes[*].VolumeId' --output text)

# wait stack status complete
while true
do
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].StackStatus' --output text)
  if [[ "${STACK_STATUS}" =~ ^(UPDATE_COMPLETE|CREATE_COMPLETE|ROLLBACK_COMPLETE)$ ]]
  then
      stack_md5sum=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs' --output text | sort | md5sum | cut -d' ' -f1)
      break
  fi
  sleep 5
done

# get stack parameters
export EIP=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`IPAddress`].OutputValue' --output text)
export VOLUME_ID=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`ExistingDataVolume`].ParameterValue' --output text)
export GITHUB_TOKEN=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`GitHubToken`].ParameterValue' --output text)
export GITHUB_ORG_NAME=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`GitHubOrgName`].ParameterValue' --output text)
export GITHUB_TEAM_SLUG=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`GitHubTeamSlug`].ParameterValue' --output text)
export LETSENCRYPT_DOMAIN=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`LetsEncryptDomain`].ParameterValue' --output text)
export LETSENCRYPT_CONFIG=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`LetsEncryptConfig`].ParameterValue' --output text)
export ARTIFACTS_S3_BUCKET=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Outputs[?OutputKey==`ArtifactsBucket`].OutputValue' --output text)
export DOCKSAL_VERSION=$(aws cloudformation describe-stacks --stack-name=${STACK_ID} --query 'Stacks[*].Parameters[?ParameterKey==`DocksalVersion`].ParameterValue' --output text)
export DOCKSAL_VERSION=${DOCKSAL_VERSION:-"master"}

# attach/detach elastic ip
if [[ "${EIP}" != "${ATTACHED_IP}" ]]
then
    # try to detach attached ip. elastic ip will be detached, but autoassigned ip remain attached
    aws ec2 disassociate-address --public-ip ${ATTACHED_IP} || true
    # try to attach elastic ip if defined in template. in case user defined wrong ip, instance will be accessible on autoassigned ip
    [[ "${EIP}" != "" ]] && aws ec2 associate-address --instance-id ${INSTANCE_ID} --public-ip ${EIP} || true
fi

# stop docker daemon before partitions manipulation
service docker stop || true

# back compatibility fix: remove automounting data-volume from /etc/fstab
sed -i "/LABEL=${DISK_LABEL}/d" /etc/fstab || true
umount -f ${MOUNT_POINT} || true

# Create build-agent user with no-password sudo access
# Forcing the uid to avoid race conditions with GCP creating project level users at the same time.
# (Otherwise, we may run into something like "useradd: UID 1001 is not unique")
if [[ "$(id -u ${BUILD_USER})" != "${BUILD_USER_UID}" ]]; then
    adduser --disabled-password --gecos "" --home ${BUILD_USER_HOME} --uid ${BUILD_USER_UID} ${BUILD_USER}
    usermod -aG sudo ${BUILD_USER}
    echo "${BUILD_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/101-${BUILD_USER}
    move_to_data ${BUILD_USER_HOME} ${MOUNT_POINT}
fi

# detach attached volume if template volume parameter changed
if [[ "${ATTACHED_VOLUME}" != "${VOLUME_ID}" ]]
then
    if [[ "${ATTACHED_VOLUME}" != "" ]]
    then
        aws ec2 detach-volume --volume-id ${ATTACHED_VOLUME} || true
        # wait detaching attached volume because attaching new volume with existing device name /dev/sdp returns error
        wait_volume_status ${ATTACHED_VOLUME} "available"
    fi
    if [[ "${VOLUME_ID}" != "" ]]
    then
        aws ec2 attach-volume --volume-id ${VOLUME_ID} --instance-id ${INSTANCE_ID} --device ${ATTACH_VOLUME_AS} || true
        wait_volume_status ${VOLUME_ID} "in-use"
    fi
fi

# mount volume if exist
if [[ "${VOLUME_ID}" != "" ]]
then
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
        wipefs -fa ${disk}
        create_part "${disk}"
        create_fs "${disk}"
        mount_part "${disk}"
    done
fi

# move existing user home directory to /data directory
move_to_data ${BUILD_USER_HOME} ${MOUNT_POINT}
# copy skelet files to user home if empty. empty home dir will be in case when stack updated with attached data volume without data
[ "$(ls -A ${MOUNT_POINT}${BUILD_USER_HOME} 2>/dev/null)" ] || cp -a /etc/skel/. ${MOUNT_POINT}${BUILD_USER_HOME}
# move docker files to /data directory
move_to_data /var/lib/docker ${MOUNT_POINT}

# Create the projects/builds directory, SSH settings: ensure ~/.ssh exists for the build user
mkdir -p ${PROJECTS_ROOT} ${BUILD_USER_HOME}/.ssh

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

# start docker daemon after partitions manipulation
service docker start || true

# update/install docksal with new or updated stack
if [[ "${old_stack_md5sum}" != "${stack_md5sum}" ]]
then
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

    # disable docker autostart
    systemctl disable docker.service
    systemctl disable docker.socket
fi

if [[ "${GITHUB_TOKEN}" != "" ]] && [[ "${GITHUB_ORG_NAME}" != "" ]] && [[ "${GITHUB_TEAM_SLUG}" != "" ]] && [[ "${old_stack_md5sum}" != "${stack_md5sum}" ]]
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

if [[ "${old_stack_md5sum}" != "${stack_md5sum}" ]]
then
    ACMESH_CONTAINER="docksal-acme.sh"
    if [[ "${LETSENCRYPT_DOMAIN}" != "" ]]
    then
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
            --log /proc/1/fd/1 || true

        if [[ -f ${CERTOUT_PATH}/${LETSENCRYPT_DOMAIN}.key ]] && [[ -f ${CERTOUT_PATH}/${LETSENCRYPT_DOMAIN}.crt ]]
        then
            sed -i '/DOCKSAL_VHOST_PROXY_DEFAULT_CERT/d' "${BUILD_USER_HOME}/.docksal/docksal.env" || true
            echo DOCKSAL_VHOST_PROXY_DEFAULT_CERT=\"${LETSENCRYPT_DOMAIN}\" | tee -a "${BUILD_USER_HOME}/.docksal/docksal.env"
            chown -R ${BUILD_USER}:${BUILD_USER} "${BUILD_USER_HOME}/"
        fi
    else
        docker rm -vf ${ACMESH_CONTAINER} 2>/dev/null || true
    fi
fi

# prepare directory for artifacts
mkdir -p ${BUILD_USER_HOME}/artifacts
sed -i '/ARTIFACTS_S3_BUCKET/d' "${BUILD_USER_HOME}/.docksal/docksal.env" || true
echo ARTIFACTS_S3_BUCKET=\"${ARTIFACTS_S3_BUCKET}\" | tee -a "${BUILD_USER_HOME}/.docksal/docksal.env"
chown ${BUILD_USER}:${BUILD_USER} "${BUILD_USER_HOME}/artifacts"

if [[ "${ARTIFACTS_S3_BUCKET}" != "" ]]
then
    apt-get -y install libgcrypt20 s3fs
    s3fs ${ARTIFACTS_S3_BUCKET} ${BUILD_USER_HOME}/artifacts -o nonempty,allow_other,iam_role,curldbg,endpoint=${AWS_DEFAULT_REGION},url=https://s3.${AWS_DEFAULT_REGION}.amazonaws.com
fi

su - build-agent -c "fin system reset"
echo "${stack_md5sum}" >/root/stack_last_update

