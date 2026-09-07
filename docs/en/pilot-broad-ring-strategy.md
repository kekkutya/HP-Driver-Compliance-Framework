# Pilot and Broad Ring Strategy

This document describes the recommended strategy for assigning devices to the Pilot and Broad rings, and the operational assumptions that make the built-in scheduling defaults an effective safeguard. Ring assignment itself is **not** implemented by HP-DCF — it is a policy-distribution decision (Intune/GPO group targeting) that determines which devices receive `Ring = Pilot` versus `Ring = Broad`. This document exists because that decision materially affects how much protection the framework's default timing actually provides.

## Design intent

The goal of the Pilot/Broad split is to prevent a defective SoftPaq from ever reaching the Broad ring without first being exercised by the Pilot ring. This is achieved purely through **time separation**, not through any automated feedback loop:

- Pilot evaluates on `WeeksOfMonth = 1,3` and deploys immediately on a successful snapshot.
- Broad evaluates on `WeeksOfMonth = 3` and deploys `BroadDelayDays` (default 21) after the same snapshot timestamp.

Because both rings evaluate on the same third-Wednesday occurrence, they freeze the same SoftPaq recommendation set on the same day. Pilot deploys that snapshot immediately, while Broad becomes eligible for the same frozen snapshot only after `BroadDelayDays` (21 days by default). In addition, Pilot may already have accumulated several weeks of operational experience with recommendations first surfaced during its week 1 evaluation.

## Recommended Pilot composition

A single random sample is not sufficient on its own. The recommended Pilot population combines two cohorts with different purposes:

### 1. Support/Help Desk devices

Devices used by IT support, service desk, and technical staff are explicitly included in Pilot regardless of random selection. Rationale:

- These users are best positioned to **notice and report** a driver/firmware regression quickly — they are more likely to recognize an HPIA-related symptom than a general end user, and they already have a direct escalation path.
- This cohort optimizes for **early detection speed**, not representativeness.

### 2. Randomized general population sample (~10%)

A random ~10% of the standard fleet, selected by a stable device attribute (for example, the last character of the serial number), is also assigned to Pilot. Rationale:

- Support/Help Desk hardware is frequently non-standard (different models, images, or configurations than the general fleet). A regression that only manifests on standard end-user hardware could pass unnoticed through a support-only Pilot.
- This cohort optimizes for **representativeness** — validating the SoftPaq against real, standard, "live" production configurations before Broad rollout.

### Selection method caveats

- **Distribution uniformity.** Selecting by the last character of the serial number assumes a roughly uniform distribution across that character. This is not guaranteed — HP serial number allocation can cluster by manufacturing batch or site. Before relying on this method at scale, validate the actual character distribution across the target fleet; a skewed distribution could under- or over-sample specific hardware batches rather than the fleet as a whole.
- **Cohort overlap.** Support/Help Desk devices may independently fall within the randomly selected serial-number slice. At small scale this can skew the effective Pilot percentage; at fleet sizes in the thousands this is expected to be negligible, but it should be a conscious assumption, not an accident, if ring coverage is ever audited.
- **Framework has no visibility into cohort composition.** `DriverDeployer` only reads a flat `Ring = Pilot|Broad` value from the registry. It does not know, and does not need to know, why a device was assigned to a given ring. This is intentional — ring assignment logic belongs entirely in policy distribution (Intune/GPO group targeting), not in the framework. The consequence is that the entire selection strategy exists only in policy configuration and in institutional knowledge; nothing in the codebase documents *why* a device is in a particular group.

## The monitoring dependency (critical)

**This is not a fail-safe mechanism.** HP-DCF has no automated feedback path from Pilot deployment outcomes to `ExcludeSoftPaqs`. The `BroadDelayDays` window only creates an *opportunity* for a human to detect and react to a problem — it does not detect or react on its own.

Concretely:

1. A Pilot device fails to install a SoftPaq (for example, HPIA/PSADT reports exit code `3020`, one or more SoftPaq installations failed).
2. Nothing in HP-DCF surfaces this centrally or blocks the Broad ring automatically.
3. Someone must notice this (through log review, RMM/monitoring integration, or a support ticket), identify the offending SoftPaq ID, and manually add it to:

   ```text
   HKLM\SOFTWARE\HPDriverComplianceFramework
     ExcludeSoftPaqs = <SoftPaq ID>
   ```

4. This must happen **before** the affected snapshot's `BroadDelayDays` window elapses. If it does not, Broad receives the same SoftPaq the Pilot ring already failed on.

### Operational requirement

A monitoring process must exist independently of HP-DCF to make this protection real. At minimum, this process should:

- Review `DriverDeployer-<ComputerName>.log` and `DriverEvaluator-<ComputerName>.log` from Pilot devices for non-success outcomes.
- Watch specifically for HPIA/deployment exit codes `3020` (installation failure) and `4099` (invalid SoftPaq number) on Pilot devices.
- Have a defined owner and a response time comfortably inside the configured `BroadDelayDays` window (not just inside it — allow margin for detection lag, ticket triage, and change approval).

Without this process, the Pilot/Broad separation still provides *some* value (temporal staggering alone reduces blast radius), but it does not provide the intended safeguard against a known-bad SoftPaq reaching the full fleet.

## Tuning `BroadDelayDays` for risk tolerance

`BroadDelayDays` is a `REG_DWORD` in the range `0..365` and can be centrally overridden per environment:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
  BroadDelayDays = <0-365>
```

- **Default (21 days)** assumes an enterprise-scale fleet (thousands of devices) where enough Pilot devices are expected to power on and check in within three weeks to produce a meaningful signal, combined with a support team that can react within the window.
- **Longer windows** (for example, 180 days for semiannual Broad rollout) suit environments prioritizing stability over currency, or environments with a smaller/less consistently online Pilot population, where more time is needed to gain confidence in a snapshot before wide deployment.
- **Shorter windows** trade detection time for faster fleet-wide currency, and should only be reduced if the monitoring process above is fast and reliable.

There is no value that makes this fully fail-safe. If the entire Pilot population is offline for the duration of `BroadDelayDays` (for example, an extended outage or holiday shutdown affecting the sampled devices), the Broad ring can still receive an unvalidated snapshot when its own delay expires. At realistic fleet sizes (thousands of devices, mixed cohorts as described above), this can be treated as a residual operational risk rather than a framework defect, provided it is explicitly understood and accepted by the deploying organization.

## Summary of assumptions

| Assumption | Why it matters | Mitigation if violated |
|---|---|---|
| At least some Pilot devices power on within the evaluation/deploy window | Pilot deployment can't happen on an offline device | Ensure Pilot includes always-on or frequently-used device classes (support staff hardware helps here) |
| Serial-number-based random selection is roughly uniform | Otherwise Pilot may not represent the standard fleet | Audit the actual last-character distribution before relying on it at scale |
| A human monitoring process reviews Pilot logs within `BroadDelayDays` | The framework will not stop a bad SoftPaq on its own | Define an explicit owner, log review cadence, and escalation path |
| Ring assignment (policy/group targeting) stays aligned with this strategy over time | Ring membership can drift as staff and devices change | Periodically re-validate Intune/GPO group membership against the intended cohorts |
