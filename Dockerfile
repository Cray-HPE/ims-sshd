# Dockerfile for IMS sshd environment
# Copyright 2018-2020, Cray Inc.
FROM dtr.dev.cray.com/baseos/opensuse:15
RUN zypper install -y openssh
COPY run_script.sh entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
ENV SSHD_OPTIONS ""
ENV IMAGE_ROOT_PARENT /mnt/image
ENV CUSTOMIZATION_SCRIPT /run_script.sh
