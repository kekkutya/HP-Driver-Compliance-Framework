# Contributing

Thank you for your interest in contributing to HP Driver Compliance Framework.

## Reporting Issues

Before opening an issue, please check whether the same or a similar issue has already been reported.

When reporting a bug, include where appropriate:

- the HP Driver Compliance Framework version;
- the affected component;
- the Windows version and relevant environment details;
- a clear description of the observed behavior;
- the expected behavior;
- relevant log output or error messages.

Do not include credentials, secrets, personal information, or other sensitive data.

For potential security vulnerabilities, follow the [Security Policy](SECURITY.md).

## Pull Requests

Changes to the production branch are accepted through pull requests.

Before submitting a pull request:

- keep the change focused on a single purpose;
- describe what the change does and why it is needed;
- update relevant documentation when behavior or configuration changes;
- ensure PowerShell scripts are syntactically valid;
- ensure ADMX/ADML resources remain valid when administrative templates are modified.

Pull requests are squash-merged to keep the production history concise.

## Development

The `main` branch represents released or release-ready production code.

Changes submitted to this repository should be suitable for inclusion in a production release and must pass the applicable validation checks before release.
