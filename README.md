# Cray IMS SSH Environment

This is the SSH environment for image creation/customization. It is the
default build environment for customizing images provided by the Cray Image
Management System (IMS).

A build environment is:
* used as a place to mount an image root into (for customization),
* for installing tools needed to customize the image root, and 
* acts as an SSH server to allow for external connections to the image
build environment so the image root can be modified externally.

This build environment can be used as a model for other build environments
that can be used by IMS.

## Getting Started

### Image Build Prerequisites
1. Docker installed.
2. Access to the Cray Docker Trusted Registry.
3. The image should ensure that an ssh server like openssh is installed.

### Entrypoint Prerequisites
In order to provide a Docker image build environment that is compatible with
IMS requirements, the image must have an `entrypoint.sh` script marked as the
docker `ENTRYPOINT` in its Dockerfile.

The `entrypoint.sh` script must:
1. Determine the `$IMS_ACTION` being undertaken, either `create` or `customize`.
2. If `create`, determine if the image creation process succeeded or failed by
the existence (or lack thereof) of the file `$IMAGE_ROOT_PARENT/build_failed`.
If successful, package the image artifacts and upload to ARS. Otherwise, if the
user indicated that they wish to debug the image build, enable a debug shell
where the image root can be inspected. No build artifacts will be uploaded from
a failed image creation to ARS.
3. If `customize`, enable a customization shell where the admin can modify the
image root. 

When enabling the SSH shell, either for debugging a failed image create or 
for customizing an existing image root, the `entrypoint.sh script` must have:
1. A mechanism to wait until the file `$IMAGE_ROOT_PARENT/ready` exists before
doing any actions in the build environment.
2. A call to start an SSH server daemon which accepts `$SSHD_OPTIONS` as an
environment variable. The `-D` option should NOT be used. The ssh server
should run as a background process. The server keys should also be in place by
calling `ssh-keygen -A` or similar to generate them.
3. A process/function which waits until `$IMAGE_ROOT_PARENT/complete` exists
to exit the script and therefore the build environment container.

See `entrypoint.sh` in this repo for an example. The entrypoint script should
execute the above steps in order.

### Environment Variables in the Container
The build environment will have all environment variables that are provided by
Kubernetes available in addition to the following:
* `$IMAGE_ROOT_PARENT`: The location where the image root will be mounted into,
e.g. `/mnt/image` where the image root will be mounted into
`/mnt/image/image-root`.
* `$SSHD_OPTIONS`: Options to pass to the SSHD instance that is started by
the entrypoint script. Do not add additional options to those contained in
this variable.
* `$CUSTOMIZATION_SCRIPT`: An script located in the build environment that can
be called and run by the `entrypoint.sh` script. In fully automated build
scenarios, this script may choose to create the `$IMAGE_ROOT_PARENT/complete`
file so that when it is finished executing, the entrypoint script will exit
as well. This script is optional.
* `$IMS_ACTION`: The action being completed, either `create` or `customize`

### Installation/Build
```
 $ docker build -t ims-sshd .
Sending build context to Docker daemon  50.69kB
...
Successfully built 95a6ead0ba94
Successfully tagged ims-sshd:latest
```

## Deployment
This image is usually deployed by the IMS due to the complexity of managing
all of the components that make up an image customization environment. See the
[IMS](https://stash.us.cray.com/projects/SCMS/repos/ims/browse) repository and
the [IMS Utilities](https://stash.us.cray.com/projects/SCMS/repos/ims-utils/browse)
repository for more information about how the build environment fits in the
image customization workflow.

## Development
Development on this repository should follow the standard CMS development
[process](https://connect.us.cray.com/confluence/x/fFGfBQ).

### Versioning
We use [SemVer](http://semver.org/) for versioning. See the `.version` file in
the repository root for the current version. Please update that version when
making changes.

## Authors
* Randy Kleinman
* Eric Cozzi

## License
Copyright 2018-2020, Cray Inc.
