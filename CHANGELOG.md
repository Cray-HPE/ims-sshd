# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
## Fixed
- CASMCMS-9226 - fix mis-spelling.

## [1.11.0] - 2024-09-13
### Dependencies
- Update from OpenSUSE 15.4 to 15.6

## [1.10.0] - 2024-03-01
### Added
- CASMCMS-8821 - add support for remote customize jobs.
- CASMCMS-8818 - add support for ssh key injection.
- CASMCMS-8897 - changes for aarch64 remote build.
- CASMCMS-8895 - allow multiple concurrent remote customize jobs.
- CASMCMS-8923 - better cleanup on unexpected exit.

### Changed
- Disabled concurrent Jenkins builds on same branch/commit
- Added build timeout to avoid hung builds

## [1.9.0] - 2023-11-30
### Changed
- CASMTRIAGE-6368 - fix setting env vars in ssh so sftp still works."

## [1.8.3] - 2023-07-11
### Changed
- CASMCMS-8708 - fix build to include metadata needed for nightly rebuilds.

## [1.8.2] - 2023-07-06
### Changed
- CASMCMS-8704 - fix env vars added to jailed env.

## [1.8.1] - 2023-06-22
### Added
- CASMCMS-8658 - add env vars with IMS job options to ssh env

## [1.8.0] - 2023-05-18
### Added
- CASMCMS-8366 - add support for arm64 docker versions
- CASMCMS-8567 - add support for arm64 image customization

### Removed
- Removed defunct files leftover from previous versioning system

## [1.7.1] - 2022-12-20
### Added
- Add Artifactory authentication to Jenkinsfile

## [1.7.0] - 2022-08-12
### Changed
- Spelling corrections.
- Added volume mounts when dkms is enabled.

## [1.6.1] - 2022-08-12
### Changed 
- CASMTRIAGE-3913 - fix the directory permissions if the incoming image has incorrect ownership.

## [1.6.0] - 2022-08-01
### Changed
- CASMCMS-7970 - update dev.cray.com server addresses.

## [1.0.0] - (no date)
