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

# Container Runs as Root

The SSHD container runs the sshd command to enable access to the image being 
built/customized. As part of the setup of sshd, container level sshd keys need 
to be created and written to /etc. 

There is future work that will hopefully mitigate any concern regarding this container 
running as root. However, until this work is completed, the container will need to run
as root.

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
[IMS](https://github.com/Cray-HPE/ims) repository and
the [IMS Utilities](https://github.com/Cray-HPE/ims-utils)
repository for more information about how the build environment fits in the
image customization workflow.

## Development
Development on this repository should follow the standard CMS development
[process](https://connect.us.cray.com/confluence/x/fFGfBQ).

## Build Helpers
This repo uses some build helpers from the 
[cms-meta-tools](https://github.com/Cray-HPE/cms-meta-tools) repo. See that repo for more details.

## Local Builds
If you wish to perform a local build, you will first need to clone or copy the contents of the
cms-meta-tools repo to `./cms_meta_tools` in the same directory as the `Makefile`. When building
on github, the cloneCMSMetaTools() function clones the cms-meta-tools repo into that directory.

For a local build, you will also need to manually write the .version, .docker_version (if this repo
builds a docker image), and .chart_version (if this repo builds a helm chart) files. When building
on github, this is done by the setVersionFiles() function.

## Versioning
The version of this repo is generated dynamically at build time by running the version.py script in 
cms-meta-tools. The version is included near the very beginning of the github build output. 

In order to make it easier to go from an artifact back to the source code that produced that artifact,
a text file named gitInfo.txt is added to Docker images built from this repo. For Docker images,
it can be found in the / folder. This file contains the branch from which it was built and the most
recent commits to that branch. 

For helm charts, a few annotation metadata fields are appended which contain similar information.

For RPMs, a changelog entry is added with similar information.

## New Release Branches
When making a new release branch:
    * Be sure to set the `.x` and `.y` files to the desired major and minor version number for this repo for this release. 
    * If an `update_external_versions.conf` file exists in this repo, be sure to update that as well, if needed.

## Authors
* Randy Kleinman
* Eric Cozzi

## Copyright and License
This project is copyrighted by Hewlett Packard Enterprise Development LP and is under the MIT
license. See the [LICENSE](LICENSE) file for details.

When making any modifications to a file that has a Cray/HPE copyright header, that header
must be updated to include the current year.

When creating any new files in this repo, if they contain source code, they must have
the HPE copyright and license text in their header, unless the file is covered under
someone else's copyright/license (in which case that should be in the header). For this
purpose, source code files include Dockerfiles, Ansible files, RPM spec files, and shell
scripts. It does **not** include Jenkinsfiles, OpenAPI/Swagger specs, or READMEs.

When in doubt, provided the file is not covered under someone else's copyright or license, then
it does not hurt to add ours to the header.
