#!/bin/bash
#
# MIT License
#
# (C) Copyright 2018-2023 Hewlett Packard Enterprise Development LP
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

PARAMETER_FILE_BUILD_FAILED=$IMAGE_ROOT_PARENT/build_failed

function wait_for_ready {
    echo "Waiting for $SIGNAL_FILE_READY flag"
    until [ -f "$SIGNAL_FILE_READY" ]
    do
        echo "Waiting for $SIGNAL_FILE_READY to exist before starting ssh environment $(date)"
        sleep 5;
    done
}

function wait_for_complete {

    echo "To mark this shell as successful, touch the file \"$SIGNAL_FILE_COMPLETE\"."
    echo "To mark this shell as failed, touch the file \"$SIGNAL_FILE_FAILED\"."
    echo "Waiting for User to mark this shell as either successful or failed."
    until [ -f "$SIGNAL_FILE_COMPLETE" ] || [ -f "$SIGNAL_FILE_FAILED" ]
    do
        sleep 5;
    done

    if [ -f "$SIGNAL_FILE_FAILED" ]
    then
        echo "$SIGNAL_FILE_FAILED exists; Shell was marked failed."
    elif [ -f "$SIGNAL_FILE_COMPLETE" ]
    then
        echo "$SIGNAL_FILE_COMPLETE exists; Shell was marked successful."
    fi

    if [ -f "$SIGNAL_FILE_COMPLETE" ]
    then
        # Remove the complete file now that we're done
        echo "Removing $SIGNAL_FILE_COMPLETE"
        rm "$SIGNAL_FILE_COMPLETE"
    fi

    echo "Exiting ssh environment"
}

function signal_exiting {
    # clean up env ars script if needed
    if [ "$SSH_JAIL" = "True" ]
    then
        echo "Removing env var file $IMAGE_ROOT_PARENT/image-root/${ENV_SCRIPT#/}"
        rm "$IMAGE_ROOT_PARENT/image-root/${ENV_SCRIPT#/}"
    fi

    # Let the buildenv-sidecar container know that we're exiting
    echo "Touching $SIGNAL_FILE_EXITING flag"
    touch "$SIGNAL_FILE_EXITING"
}

function run_user_shell {
    # Wait for the ready file to be available
    wait_for_ready

    # Setup SSH jail
    if [ "$SSH_JAIL" = "True" ]
    then
        chmod 755 "$IMAGE_ROOT_PARENT"
        chown root:root "$IMAGE_ROOT_PARENT"
        chown root:root "$IMAGE_ROOT_PARENT/image-root"
        echo "Match User root" >> "$SSHD_CONFIG_FILE"
        echo "ChrootDirectory $IMAGE_ROOT_PARENT/image-root" >> "$SSHD_CONFIG_FILE"
        SIGNAL_FILE_COMPLETE=$IMAGE_ROOT_PARENT/image-root/tmp/complete
        SIGNAL_FILE_FAILED=$IMAGE_ROOT_PARENT/image-root/tmp/failed
    fi

    # If setting up for dkms permissions, do that now
    echo "JOB_ENABLE_DMKS: $JOB_ENABLE_DKMS"
    local is_dkms=$(echo $JOB_ENABLE_DKMS | tr '[:upper:]' '[:lower:]')
    echo "is_dkms=$is_dkms"
    if [ "$is_dkms" = "true" ]; then
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
    else
        echo "DKMS not enabled"
    fi

    # If setting up for arm64 emulation, do that now
    echo "Checking build architecture: $BUILD_ARCH"
    if [ "$BUILD_ARCH" == "aarch64" ]; then
        echo "Build architecture is aarch64"
        # Regiser qemu-aarch64-static to act as an arm interpreter for arm builds 
        if [ ! -d /proc/sys/fs/binfmt_misc ] ; then
            echo "- binfmt_misc does not appear to be loaded or isn't built in."
            echo "  Trying to load it..."
            if ! modprobe binfmt_misc ; then
                echo "FATAL: Unable to load binfmt_misc"
                exit 1;
            fi
        fi

        # mount the emulation filesystem
        if [ ! -f /proc/sys/fs/binfmt_misc/register ] ; then
            echo "- The binfmt_misc filesystem does not appear to be mounted."
            echo "  Trying to mount it..."
            if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
                echo "FATAL:  Unable to mount binfmt_misc filesystem."
                exit 1
            fi
        fi

        # register qemu for aarch64 images 
        if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] ; then
            echo "- Setting up QEMU for ARM64"
            echo ":qemu-aarch64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" >> /proc/sys/fs/binfmt_misc/register
        fi
    fi

    ## Set up the env vars we want to make available to users
    # Add vars to a script file
    echo "export IMS_JOB_ID=$IMS_JOB_ID" >> "$ENV_SCRIPT"
    echo "export IMS_ARCH=$BUILD_ARCH" >> "$ENV_SCRIPT"
    echo "export IMS_DKMS_ENABLED=$JOB_ENABLE_DKMS" >> "$ENV_SCRIPT"

    # different route for providing an interactive shell vs executing a command via ssh
    echo 'if [[ -z "$SSH_ORIGINAL_COMMAND" ]]; then' >> "$ENV_SCRIPT"
    echo '    exec bash -il' >> "$ENV_SCRIPT"
    echo 'else' >> "$ENV_SCRIPT"
    echo '    eval $SSH_ORIGINAL_COMMAND' >> "$ENV_SCRIPT"
    echo 'fi' >> "$ENV_SCRIPT"

    # Force that script to be run on login from ssh
    echo "ForceCommand $ENV_SCRIPT" >> "$SSHD_CONFIG_FILE"
## TODO - use this for forwarding commands to remote docker

    # If this is a jailed env, env vars script needs to be copied to image root
    if [ "$SSH_JAIL" = "True" ]
    then
        echo "Copying env var script to: $IMAGE_ROOT_PARENT/image-root/${ENV_SCRIPT#/}"
        cp "$ENV_SCRIPT" "$IMAGE_ROOT_PARENT/image-root/${ENV_SCRIPT#/}"
    fi

    # Start the SSH server daemon
    ssh-keygen -A
    chown -R root:root /etc/cray/ims
    /usr/sbin/sshd $SSHD_OPTIONS

    # Perform any other bootstrapping tasks here or run a script
    # located in the build environment
    if [ ! -z $CUSTOMIZATION_SCRIPT ]
    then
        . $CUSTOMIZATION_SCRIPT
    fi

    # Enter wait loop for $SIGNAL_FILE_COMPLETE to show up
    wait_for_complete

    # Let the buildenv-sidecar container know that we're exiting
    signal_exiting
}

function should_run_user_shell {
    case "$IMS_ACTION" in
        create)
            if [ -f "$PARAMETER_FILE_BUILD_FAILED" ]; then
                if [[ $(echo "$ENABLE_DEBUG" | tr [:upper:] [:lower:]) = "true" ]]; then
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
            echo "Unknown IMS Action: $IMS_ACTION. Not running user shell."
            return 1
            ;;
    esac
  return 1
}

# Do we need to present the user with a SSH shell?
if should_run_user_shell; then
  run_user_shell
fi
