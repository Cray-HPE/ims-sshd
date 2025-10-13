#!/bin/bash
#
# MIT License
#
# (C) Copyright 2018-2025 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# Entry point script for the default Cray image customization build environment
#
#  Usage:
#    /entrypoint.sh [/mnt/image]
#
# +--------------------------------------------+         +--------------------------------------------+
# |             Sidecar Container              |         |                SSH Container               |
# +--------------------------------------------+         +--------------------------------------------+
# |                                            |         |                                            |
# |  1. Sidecar container creates              |         |                                            |
# |     SSHD and authorized_keys               |         |                                            |
# |     config files in shared                 |         |                                            |
# |     /etc/cray/ims volume                   |         |                                            |
# |  2. Remove SIGNAL_FILE_COMPLETE            |         |                                            |
# |     and SIGNAL_FILE_EXITING flags          |         |                                            |
# |     if they exist.                         |         |                                            |
# |  3. Touch SIGNAL_FILE_READY +-------------------------> 4. Wait for @SIGNAL_FILE_READY            |
# |                                            |         |  5. Start SSHD daemon using config <---------+ User accesses SSH environment
# |                                            |         |     files in /etc/cray/ims shared          |
# |                                            |         |     volume (see $SSHD_OPTIONS)             |
# |                                            |         |  6. Wait for user to touch  <----------------+ User touches SIGNAL_FILE_COMPLETE file
# |                                            |         |     $SIGNAL_FILE_COMPLETE or               |
# |                                            |         |     $SIGNAL_FILE_FAILED                    |
# |                                            |         |  7. Start orderly shutdown of SSH          |
# |                                            |         |     Container                              |
# |                                            |         |     a) Remove SIGNAL_FILE_COMPLETE file    |
# |  8. Wait for SIGNAL_FILE_EXITING <-----------------------+ b) Touch SIGNAL_FILE_EXITING           |
# |  9. Remove SIGNAL_FILE_EXITING file        |         |                                            |
# | 10. Remove SIGNAL_FILE_COMPLETE file       |         |                                            |
# |     (should be removed by SSH Container,   |         |                                            |
# |      but just in case...)                  |         |                                            |
# | 11. Call package_and_upload.sh if          |         |                                            |
# |     appropriate.                           |         |                                            |
# |                                            |         |                                            |
# +--------------------------------------------+         +--------------------------------------------+

IMAGE_ROOT_PARENT=${1:-/mnt/image}
SIGNAL_FILE_READY=$IMAGE_ROOT_PARENT/ready
SIGNAL_FILE_COMPLETE=$IMAGE_ROOT_PARENT/complete
SIGNAL_FILE_EXITING=$IMAGE_ROOT_PARENT/exiting
SIGNAL_FILE_FAILED=$IMAGE_ROOT_PARENT/failed

REMOTE_PORT_FILE=$IMAGE_ROOT_PARENT/remote_port
REMOTE_PORT=""

PARAMETER_FILE_BUILD_FAILED=$IMAGE_ROOT_PARENT/build_failed
PARAMETER_FILE_POD_ERROR=$IMAGE_ROOT_PARENT/pod_error

# NOTE: these are locations within the remote container
SIGNAL_FILE_REMOTE_EXITING=/mnt/image/remote_exiting
SIGNAL_FILE_REMOTE_ERROR=image/remote_error

# Number of consecutive heartbeat failures before assuming remote job is no longer running
# Default is 12 (1 minute if checking every 5 seconds) - set in IMS configuration map
HEARTBEAT_ERROR_LIMIT=${REMOTE_HEARTBEAT_TIMEOUT_COUNT:-12}

function wait_for_ready {
    echo "Waiting for $SIGNAL_FILE_READY flag"
    until [[ -f ${SIGNAL_FILE_READY} ]]
    do
        echo "Waiting for $SIGNAL_FILE_READY to exist before starting ssh environment $(date)"
        sleep 5;
    done
}

function wait_for_local_complete {
    until [[ -f ${SIGNAL_FILE_COMPLETE} || -f ${SIGNAL_FILE_FAILED} ]]
    do
        sleep 5;
    done
}

function wait_for_remote_complete {
    # Loop forever until the user is done
    HEARTBEAT_ERROR_COUNT=0
    while [ true ]
    do
        # Look for the exiting flag in the remote job
        if ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "test -f /tmp/ims_${IMS_JOB_ID}/${SIGNAL_FILE_REMOTE_EXITING}"; then
            return 0
        fi

        # Look for the error flag in the remote job
        if ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "test -f /tmp/ims_${IMS_JOB_ID}/${SIGNAL_FILE_REMOTE_ERROR}"; then
            # a return value of 0 indicates file is present - remote complete
            echo "Remote job reported a container error - exiting wait loop"
            touch "${SIGNAL_FILE_FAILED}" "${PARAMETER_FILE_POD_ERROR}"
            return 1
        fi

        # make sure the remote job is still running
        ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman exec ims-${IMS_JOB_ID} echo heartbeat">/dev/null 2>&1
        # a return value of 0 indicates the container is running
        if [[ $? -ne 0 ]]; then
            # Heartbeat failed - not sure if this is a pod failure or temporary network issue
            if [[ ${HEARTBEAT_ERROR_COUNT} -ge ${HEARTBEAT_ERROR_LIMIT} ]]; then
                # After 12 consecutive errors (1 minute) assume the remote job is no longer running
                echo "Remote job is no longer accessible after ${HEARTBEAT_ERROR_LIMIT} consecutive errors - exiting wait loop"
                touch "${SIGNAL_FILE_FAILED}" "${PARAMETER_FILE_POD_ERROR}"
                return 1
            fi

            # Increment error count and try again
            HEARTBEAT_ERROR_COUNT=$((HEARTBEAT_ERROR_COUNT+1))
            echo "Remote container heartbeat failed - error count: ${HEARTBEAT_ERROR_COUNT}"
        else
            # Heartbeat succeeded - reset error count
            HEARTBEAT_ERROR_COUNT=0
        fi

        sleep 5;
    done
}

function wait_for_complete {

    echo "To mark this shell as successful, touch the file \"${SIGNAL_FILE_COMPLETE}\"."
    echo "To mark this shell as failed, touch the file \"${SIGNAL_FILE_FAILED}\"."
    echo "Waiting for User to mark this shell as either successful or failed."

    # If this is a remote build, we need to check the remote job for completion
    RC=0
    if [[ -n ${REMOTE_BUILD_NODE} ]]; then
        # pass along the return code from the wait_for_remote_complete function in case
        # we need to signal an error with the remote pod
        wait_for_remote_complete
        RC=$?
    else
        wait_for_local_complete
    fi

    # check the results of the run now that the user shell has exited
    if [[ -f ${SIGNAL_FILE_FAILED} ]]
    then
        echo "${SIGNAL_FILE_FAILED} exists; Shell was marked failed."
    elif [[ -f ${SIGNAL_FILE_COMPLETE} ]]
    then
        echo "${SIGNAL_FILE_COMPLETE} exists; Shell was marked successful."
    fi

    if [[ -f ${SIGNAL_FILE_COMPLETE} ]]
    then
        # Remove the complete file now that we're done
        echo "Removing ${SIGNAL_FILE_COMPLETE}"
        rm "${SIGNAL_FILE_COMPLETE}"
    fi

    echo "Exiting ssh environment"
    return $RC
}

function signal_exiting {
    # Let the buildenv-sidecar container know that we're exiting
    echo "Touching ${SIGNAL_FILE_EXITING} flag"
    touch "${SIGNAL_FILE_EXITING}"
}

function run_user_shell {
    # Wait for the ready file to be available
    wait_for_ready

    ## Set up the env vars we want to make available to users
    # Add vars to a script file - NOTE: must all be on one line
    # NOTE:
    #  - all env vars must be on one line
    #  - this must be before the 'Match' line in a jailed setup
    echo "SetEnv IMS_JOB_ID=$IMS_JOB_ID IMS_ARCH=$BUILD_ARCH IMS_DKMS_ENABLED=$JOB_ENABLE_DKMS REMOTE_BUILD_NODE=$REMOTE_BUILD_NODE" >> "$SSHD_CONFIG_FILE"

    # Set up forwarding to remote node if needed
    if [[ -n ${REMOTE_BUILD_NODE} ]]; then
        # if the remote port file does not exist, bail
        if [[ ! -f ${REMOTE_PORT_FILE} ]]; then
            echo "ERROR: file with remote port missing - can not proceed with remote job!"
            touch "${SIGNAL_FILE_FAILED}"
            signal_exiting
            return 1
        fi

        # get remote port file into env var REMOTE_PORT
        REMOTE_PORT=$(cat ${REMOTE_PORT_FILE})

        # set up cleanup in case this exits unexpectedly
        trap clean_exit SIGTERM SIGINT SIGKILL

        # prepare the ssh keys to access the remote node
        mkdir -p ~/.ssh
        cp /etc/cray/remote-keys/id_ecdsa ~/.ssh
        chmod 600 ~/.ssh/id_ecdsa
        ssh-keygen -y -f ~/.ssh/id_ecdsa > ~/.ssh/id_ecdsa.pub

        # set up port forwarding to the remote node
        REMOTE_NODE_IP=$(getent hosts ${REMOTE_BUILD_NODE} | awk '{ print $1 }')
        iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination "${REMOTE_NODE_IP}":"${REMOTE_PORT}"
        iptables -t nat -A POSTROUTING -j MASQUERADE
    fi

    # Setup SSH jail
    if [[ $SSH_JAIL == "True" ]];
    then
        chmod 755 "$IMAGE_ROOT_PARENT"
        chown root:root "$IMAGE_ROOT_PARENT"
        chown root:root "$IMAGE_ROOT_PARENT/image-root"

        # if this is a remote job, chrootDir is set up on remote config
        if [[ -z ${REMOTE_BUILD_NODE} ]]; then
            echo "Match User root" >> "${SSHD_CONFIG_FILE}"
            echo "ChrootDirectory ${IMAGE_ROOT_PARENT}/image-root" >> "${SSHD_CONFIG_FILE}"

            # If this is not a remote job, change location of complete files
            SIGNAL_FILE_COMPLETE=${IMAGE_ROOT_PARENT}/image-root/tmp/complete
            SIGNAL_FILE_FAILED=${IMAGE_ROOT_PARENT}/image-root/tmp/failed
        fi
    fi

    # If setting up for dkms permissions, do that now
    echo "JOB_ENABLE_DKMS: ${JOB_ENABLE_DKMS}"
    local is_dkms=$(echo "${JOB_ENABLE_DKMS}" | tr '[:upper:]' '[:lower:]')
    echo "is_dkms=${is_dkms}"
    if [[ ${is_dkms} == "true" ]]; then
        if [[ -n ${REMOTE_BUILD_NODE} ]]; then
            echo " dkms mounts not set in sshd pod for remote jobs"
        else
            if mount -t sysfs /sysfs /mnt/image/image-root/sys; then
                echo "Mounted /sys"
            else
                echo "Failed to mount /sys"
            fi
            if mount -t proc /proc /mnt/image/image-root/proc; then
                echo "Mounted /proc"
            else
                echo "Failed to mount /proc"
            fi
            if mount -t devtmpfs /devtmpfs /mnt/image/image-root/dev; then
                echo "Mounted /dev"
            else
                echo "Failed to mount /dev"
            fi
        fi
    else
        echo "DKMS not enabled"
    fi

    # If setting up for arm64 emulation, do that now
    echo "Checking build architecture: ${BUILD_ARCH}"
    if [[ ${BUILD_ARCH} == "aarch64" ]]; then
        echo "Build architecture is aarch64"
        # Register qemu-aarch64-static to act as an arm interpreter for arm builds
        if [[ ! -d /proc/sys/fs/binfmt_misc ]]; then
            echo "- binfmt_misc does not appear to be loaded or isn't built in."
            echo "  Trying to load it..."
            if ! modprobe binfmt_misc ; then
                echo "FATAL: Unable to load binfmt_misc"
                exit 1;
            fi
        fi

        # mount the emulation filesystem
        if [[ ! -f /proc/sys/fs/binfmt_misc/register ]] ; then
            echo "- The binfmt_misc filesystem does not appear to be mounted."
            echo "  Trying to mount it..."
            if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
                echo "FATAL:  Unable to mount binfmt_misc filesystem."
                exit 1
            fi
        fi

        # register qemu for aarch64 images 
        if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] ; then
            echo "- Setting up QEMU for ARM64"
            echo ":qemu-aarch64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" >> /proc/sys/fs/binfmt_misc/register
        fi
    fi

    # Make sure ownership of dir is correct
    chown -R root:root /etc/cray/ims

    # Start the SSH server daemon or set up port forwarding
    if [[ -z ${REMOTE_BUILD_NODE} ]]; then
        ssh-keygen -A
        /usr/sbin/sshd $SSHD_OPTIONS
    fi

    # Perform any other bootstrapping tasks here or run a script
    # located in the build environment
    if [[ ! -z ${CUSTOMIZATION_SCRIPT} ]]; then
        . ${CUSTOMIZATION_SCRIPT}
    fi

    # Enter wait loop for $SIGNAL_FILE_COMPLETE to show up - pass along return code
    # This will mark the k8s job in an error state if the remote job exits with an error
    wait_for_complete
    RC=$?

    # If this is a remote customize build, we need to pull the results back
    # from the remote node.
    if [[ -n ${REMOTE_BUILD_NODE} ]]; then
        fetch_remote_artifacts
    fi

    # Let the buildenv-sidecar container know that we're exiting
    signal_exiting

    # pass along the return code from the wait_for_complete function
    return $RC
}

function clean_exit {
    # handle a signal terminating the process
    echo "Abrupt exiting..."

    # remote container should still be running - need to kill it
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman stop ims-${IMS_JOB_ID}"

    # now that container has stopped, we can proceed with the normal cleanup
    clean_remote_node

    exit 1
}

function clean_remote_node {
    # delete artifacts off of remote host
    # NOTE: need to prune the anonymous volume explicitly to free up the space
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "rm -rf /tmp/ims_${IMS_JOB_ID}/"
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman rm ims-${IMS_JOB_ID}"
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman rmi ims-remote-${IMS_JOB_ID}:1.0.0"
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman volume prune -f"
}

function fetch_remote_artifacts {
    # check the results of the build
    ssh -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}" "podman cp ims-${IMS_JOB_ID}:/mnt/image/complete /tmp/ims_${IMS_JOB_ID}/"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        # Failed rc indicates file not present
        echo "ERROR: Error reported from customize job."

        # make sure the remote node artifacts are cleaned up
        clean_remote_node

        # signal we are done
        echo "Touching failed flag: ${SIGNAL_FILE_FAILED}"
        touch "${SIGNAL_FILE_FAILED}"
    else
        echo "Remote job succeeded - fetching remote artifacts..."

        # copy image files from remote machine to job pod
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/*" "${IMAGE_ROOT_PARENT}"

        # make sure the remote node artifacts are cleaned up
        clean_remote_node

        # signal we are done
        touch "${SIGNAL_FILE_COMPLETE}"
    fi
}

function should_run_user_shell {
    case "$IMS_ACTION" in
        create)
            if [[ -f $PARAMETER_FILE_BUILD_FAILED ]]; then
                if [[ $(echo "${ENABLE_DEBUG}" | tr [:upper:] [:lower:]) = "true" ]]; then
                    echo "Running user shell for failed create action"
                    return 0
                else
                    echo "Not running user shell for failed create action"
                    return 1
                fi
            else
                echo "Not running user shell for successful create action"
                return 1
            fi
            ;;
        customize)
            echo "Running user shell for customize action"
            return 0
            ;;
         *)
            echo "Unknown IMS Action: ${IMS_ACTION}. Not running user shell."
            return 1
            ;;
    esac
  return 1
}

# Do we need to present the user with a SSH shell?
if should_run_user_shell; then
  # A non-zero return code indicates the user shell failed - used to signal that
  # the remote job container failed in an unexpected way. This will mark the k8s job
  # in an error state.
  run_user_shell
  exit $?
fi
