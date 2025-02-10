#
# MIT License
#
# (C) Copyright 2018-2024 Hewlett Packard Enterprise Development LP
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

# Dockerfile for IMS sshd environment
FROM artifactory.algol60.net/csm-docker/stable/docker.io/opensuse/leap:15.6 as base

# Create a user with UID 65534 and GID 65534 (nobody user)
RUN groupadd --gid 65534 nobody || true && \
    useradd -u 65534 -g 65534 -ms /bin/bash nobody

# Add privilege into sudoers file
RUN echo 'nobody ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Switch the user to non-root
USER 65534:65534

# Add tools for remote access
RUN zypper install -y openssh wget squashfs tar python3 python3-pip podman vi

# Apply security patches
COPY zypper-refresh-patch-clean.sh /
RUN /zypper-refresh-patch-clean.sh && rm /zypper-refresh-patch-clean.sh

# Install qemu-aarch64-static binary to handle arm64 emulation if needed
RUN wget https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static && \
    mv ./qemu-aarch64-static /usr/bin/qemu-aarch64-static && chmod +x /usr/bin/qemu-aarch64-static

COPY run_script.sh force_cmd.sh entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
ENV SSHD_OPTIONS ""
ENV IMAGE_ROOT_PARENT /mnt/image
ENV CUSTOMIZATION_SCRIPT /run_script.sh
