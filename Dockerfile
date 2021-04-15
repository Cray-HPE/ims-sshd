# Dockerfile for IMS sshd environment
# Copyright 2018-2021, Hewlett Packard Enterprise Development LP
FROM arti.dev.cray.com/baseos-docker-master-local/opensuse-leap:15.2
RUN zypper install -y openssh
COPY run_script.sh entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
ENV SSHD_OPTIONS ""
ENV IMAGE_ROOT_PARENT /mnt/image
ENV CUSTOMIZATION_SCRIPT /run_script.sh
