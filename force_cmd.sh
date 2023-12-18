#!/bin/bash
#
# MIT License
#
# (C) Copyright 2023-2024 Hewlett Packard Enterprise Development LP
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
if [[ -z "$SSH_ORIGINAL_COMMAND" ]]; then
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2022 root@${REMOTE_BUILD_NODE}
# NOTE: this does not currently work for sftp - try somthing like below to make it work?
#elif [[ "$SSH_ORIGINAL_COMMAND" == "internal-sftp" ]]; then
#    sftp -P 2022 root@${REMOTE_BUILD_NODE}
else
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2022 root@${REMOTE_BUILD_NODE} $SSH_ORIGINAL_COMMAND
fi
