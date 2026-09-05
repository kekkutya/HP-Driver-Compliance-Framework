# Changelog

All notable changes to HP Driver Compliance Framework are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses semantic versioning for framework releases.

## [Unreleased]

### Changed

- Updated repository artwork with a wide README banner and GitHub Social Preview image.
- Added an MIT license badge to the README.
- Replaced the hard-coded Hungarian DriverDeployment completion message with the native localized PSAppDeployToolkit completion message.

## [1.0.5] - 2026-09-05

### Added

- Added the MIT license for original HP-DCF source code and documentation.
- Added third-party notices and bundled license copies for redistributed dependencies.
- Added release validation for required publication and license metadata.
- Added release validation to prevent redistribution of HP Image Assistant executable payloads.

### Changed

- Updated framework and deployment artwork to independent HP-DCF branding.
- Included publication and third-party license files in release packages.
- Updated the framework baseline to 1.0.5, DriverEvaluator to 1.0.2, and DriverDeployer to 1.0.3.
- Removed redundant DriverEvaluator HPIA version logging.
- Updated DriverDeployment logging to use the HP-DCF report location.

## [1.0.4] - 2026-09-04

### Changed

- Updated the framework baseline from 1.0.3 to 1.0.4.
- Synchronized current version references across the English and Hungarian documentation.

## [1.0.3] - 2026-09-04

### Added

- Added HP Image Assistant lifecycle management to DriverEvaluator and DriverDeployer ForceAll processing using HP CMSL.
- Added English and Hungarian Quick Start guides.
- Added automated documentation version synchronization through `tools/Sync-VersionReferences.ps1`.
- Added repository editor and encoding policy through `.editorconfig`.
- Restored repository community and security files in the development baseline.

### Changed

- DriverEvaluator now verifies and, when required, installs or updates HP Image Assistant before evaluation.
- DriverDeployer ForceAll remediation now verifies and, when required, installs or updates HP Image Assistant before direct remediation.
- Removed duplicate HPIA lifecycle management from the DriverDeployment PSADT wrapper.
- Updated the framework baseline to 1.0.3, DriverEvaluator to 1.0.1, and DriverDeployer to 1.0.2.

## [1.0.2] - 2026-08-28

### Added

- Added persistent `.deployed` snapshot completion markers that record the source snapshot execution ID, deployment time, and HPIA exit code.

### Fixed

- Prevented successful evaluation snapshots from being deployed repeatedly.
- Added cleanup of stale deferred deployment state when its source snapshot has already been deployed.
- Extended snapshot retention and ForceAll cleanup to include deployment completion markers.

### Changed

- Added release-time version placeholders for the framework and DriverDeployer PSADT packages.
- Updated the framework baseline to 1.0.2 and DriverDeployer to 1.0.1.

## [1.0.1] - 2026-08-27

### Added

- Added contribution guidelines, security policy, and structured bug and feature request templates.
- Added project status and technology badges to the README.
- Added independent Administrative Template version tracking.
- Added additional release validation for repository and Administrative Template metadata.

### Changed

- Updated the Administrative Template to version 1.0.1.
- Updated the framework baseline to 1.0.1.
- Updated English and Hungarian documentation and Administrative Template localization.

## [1.0.0] - 2026-08-25

### Added

- Initial stable release of HP Driver Compliance Framework.
- DriverEvaluator for scheduled HP update evaluation and immutable evaluation snapshot generation.
- DriverDeployer for controlled deployment from evaluation snapshots.
- Pilot and Broad deployment ring support.
- Policy-driven configuration through Administrative Templates.
- Snapshot retention, exclusions, deployment handoff, and defer lifecycle management.
- ForceAll remediation workflow.
- PSAppDeployToolkit-based interactive deployment.
- English and Hungarian technical documentation.
- Automated release packaging and framework/component version injection.

Earlier `0.x` tags represent pre-1.0 development milestones and are not individually documented here.

[Unreleased]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.5
[1.0.4]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.4
[1.0.3]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.3
[1.0.2]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.2
[1.0.1]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.1
[1.0.0]: https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/tag/v1.0.0
