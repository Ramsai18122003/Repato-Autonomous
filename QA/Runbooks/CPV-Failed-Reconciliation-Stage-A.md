# CPV failed preparation reconciliation — Stage A

Stage A adds an authenticated `cpv-preparation-reconcile-failed` operation for one exact request. It accepts only a persisted `OutcomeUnknown` receipt whose private failure record contains `InvalidDataException: preparation-exited-without-result`, and verifies the active marker and saved request identities, runner request identities and paths, the unchanged fixed-fixture model hash, no result or Revit lock markers, and an empty local Revit process snapshot. Process enumeration, model exclusivity, and evidence reads fail closed. A success records `FailedReconciled`, keeps `CleanupVerified=false`, records no rollback claim, persists the terminal receipt before removing the matching active marker, and retains request, failure, and replay evidence.

The canonical operation is separate and revision guarded. It contacts the agent using the persisted request IDs, validates the returned terminal receipt, then records `FailedReconciled` and its receipt in one normal canonical store transaction. It does not prepare a fixture, create an approval, or dispatch native QA. If the agent response is lost after its durable transition, repeat the same canonical command with the same request and the current canonical revision; no new request is generated. If the canonical commit response is lost, status and the same command are idempotent.

## Stage A verification

Run only the contract and isolated-store checks:

```powershell
dotnet run --project .\CpvPreparation.ContractTests\CpvPreparation.ContractTests.csproj -c Release
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\AgentOrchestration\Test-CpvPreparationFailedReconciliation.ps1
```

The tests inject process-boundary outcomes and use temporary files/stores. They never dispatch Revit or read/write the production QA task store. The existing `Test-CpvPreparationRecoveryTransaction.ps1` exercises the earlier full recovery workflow; it assumes the checked-in canonical task fixture contains a pending approval with an expiry. If that assumption fails, do not replace its fixture from live data or run it against the real store; use an isolated canonical fixture for the separate recovery contract.

## Stage B — authorization and deployment boundary

Stage B is not authorized by Stage A. The guarded installer now has a narrowly scoped exception for this exact unresolved request. With an active marker present, it requires both `-ReconcileRequestId 9953e14c15524fe09440d1c7d7353950` and `-TaskId task-bf61fe7f22d74df7a92599681da5919e`. It authenticates the current user and installed agent, verifies the exact old agent version, authenticated capabilities and request status, marker/receipt/failure/runner identities, candidate manifest and runtime hashes, unchanged fixture/model hash, absent result and lock files, no Revit process, and prior runtime/task rollback evidence. It then retains and validates the installer's rollback copy, starts the upgraded agent, confirms the failed status and protected evidence are unchanged, and verifies the new reconciliation capability. The unresolved active marker and diagnostics are preserved. Every other active-marker case remains prohibited. The exception does not start preparation, dispatch, replay, approve, or launch Revit.

The installer rollback token is held in process memory. The guarded wrapper restores and verifies the prior runtime/task for handled failures and its synthetic interruption cases. A hard process termination or machine/power loss during the bootstrap install cannot be guaranteed recoverable by this implementation; this remains a release risk and requires a separately reviewed durable install journal before claiming power-loss safety.

After the guarded installer change is reviewed, Stage B still requires separate explicit authorization for each boundary:

1. Commit the scoped Launch Agent, orchestration, tests, and runbook changes. The immutable release packager requires a committed source identity; no unrelated dirty file may be included.
2. Build and run all Launch Agent protocol, CPV preparation, canonical transaction, and installer rollback tests. Package with `New-QaLaunchAgentRelease.ps1`; record the exact release path, source commit, version, manifest hash, and file hashes.
3. Obtain explicit authorization to install that exact release using the request-bound command below from elevated PowerShell. Replace the placeholders only with the independently verified immutable release directory and manifest SHA-256. No product add-in or Revit deployment is part of this step.

   ```powershell
   & .\AgentOrchestration\Install-CpvPreparationAgentCandidate.ps1 `
     -ReleaseRoot <validated-release-root> `
     -ManifestSha256 <release-manifest-sha256> `
     -ReconcileRequestId 9953e14c15524fe09440d1c7d7353950 `
     -TaskId task-bf61fe7f22d74df7a92599681da5919e `
     -Execute
   ```

   The installer requires elevated PowerShell, stops/restarts only the exact scheduled Launch Agent, retains rollback evidence until installed runtime/task integrity and authenticated capability/status/evidence checks pass, and automatically restores the prior runtime/task on handled failure. Do not treat this in-memory rollback as protection against a hard process or machine interruption.
4. Re-read the canonical task and current revision; verify request/task/workflow/attempt/run IDs and that no pending approval exists. From the authenticated `RAMSAI\RepatoQA` session, first run the read-only status command:

   ```powershell
   & .\AgentOrchestration\Invoke-CpvPreparationRecovery.ps1 -Operation status -TaskId task-bf61fe7f22d74df7a92599681da5919e
   ```

   Then, only after the terminal receipt and unchanged evidence satisfy the reconciliation gates, run `Invoke-CpvPreparationRecovery.ps1 -Operation reconcile-failed -TaskId task-bf61fe7f22d74df7a92599681da5919e -ExpectedTaskRevision <observed-revision>` once. Verify canonical status, agent status, unchanged task request IDs, retained diagnostics/reservations, absent active marker, and zero pending approvals. Do not run begin, dispatch, complete, retry, or native QA as part of reconciliation.
5. If post-install verification fails before reconciliation, use the installer's retained rollback token through `Restore-RepatoQaLaunchAgentBootstrapInstall`; verify the prior installed manifest/task integrity and authenticated health. If reconciliation has durably written `FailedReconciled`, do not roll back agent code before confirming canonical persistence and marker state; resume the same request-bound canonical update instead.

The only operation authorized in Stage A is offline source/test work. Stage B installation and live reconciliation need separate explicit authorization. Revit remains prohibited throughout.
