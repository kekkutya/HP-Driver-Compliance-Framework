# HP Driver Compliance Framework Documentation

This directory contains the canonical English technical documentation for **HP Driver Compliance Framework (HP-DCF) v1.0.4**.

The framework separates HP update evaluation from deployment:

```text
DriverEvaluator
      |
      v
Validated Evaluation snapshot
      |
      v
DriverDeployer
      |
      +-- Normal / ForceRun --> DriverDeployment PSADT --> HPIA
      |
      +-- ForceAll ---------> HPIA directly
```

## Documents

- [Quick Start](quick-start.md)
- [Architecture](architecture.md)
- [Configuration reference](configuration.md)
- [DriverEvaluator](DriverEvaluator.md)
- [DriverDeployer](DriverDeployer.md)
- [Deployment](deployment.md)
- [Troubleshooting](troubleshooting.md)

The repository root [README](../../README.md) provides the short project overview.
