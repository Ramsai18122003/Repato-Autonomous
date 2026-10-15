# CPV installer bundle

This bundle is a source-bound offline package for the Launch Agent installer and the CPV recovery/status commands. It contains the installer, helper, bootstrap, durable install recovery command, CPV recovery modules, their PowerShell import dependencies, and the pinned `CreatePlanViewsEmpty.rvt` fixture. It embeds copies of the verified Launch Agent 1.0.18 candidate and 1.0.17 rollback release. The existing release directories are read-only inputs and are never overwritten.

## Package from a clean source checkout

Use a clean checkout at the reviewed installer source commit. The packager rejects a dirty checkout, a different HEAD, missing or modified committed dependencies, an invalid fixture hash, runtime manifest mismatch, rollback manifest mismatch, and an existing bundle destination.

The packager is separately source controlled. Run it from a clean checkout of its reviewed tooling commit; the bundle records both commits and includes hashes for the three packaging/validation scripts. The installer payload remains bound to the six-file baseline and committed transitive dependencies at `15320f410e43c7627d6e3ae61424ef20aa23d29e`.

```powershell
$source = 'C:\Repato-Autonomous\Worktrees\cpv-installer-source-15320'
$tool = 'C:\Repato-Autonomous\Worktrees\cpv-installer-bundle-tool'
$runtime = 'C:\Repato-Autonomous\Source\DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.18+4b0066247088'
$rollback = 'C:\Repato-Autonomous\Source\DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.17+4b0066247088'
$bundleParent = 'C:\Repato-Autonomous\Source\DeploymentCandidates\CpvInstallerBundles'
& "$tool\AgentOrchestration\New-CpvInstallerBundle.ps1" `
  -SourceRoot $source `
  -SourceCommit 15320f410e43c7627d6e3ae61424ef20aa23d29e `
  -RuntimeReleaseRoot $runtime `
  -RuntimeManifestSha256 B7077E707DD052AB7E233D6865824C90345D5629AA77CC750E7D34C29598AB32 `
  -RollbackReleaseRoot $rollback `
  -RollbackManifestSha256 7232FC5A028B4C5F6E3C3A9B5FD4831F94380AF135BC76046EF918D9A8B842F1 `
  -ToolCommit <reviewed-bundle-tool-commit> `
  -FixedFixturePath 'C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt' `
  -BundleParent $bundleParent
```

Keep the returned `BundleRoot` and `ManifestSha256`. The directory name is unique to the source commit; duplicate output paths fail. Each packaged file is listed with SHA-256. Source files are checked against Git objects at the specified commit. The fixed fixture is separately pinned by the committed recovery module's SHA-256 constant. The runtime and rollback releases retain their own manifests and source commits inside the bundle.

Validate the completed bundle before any use:

```powershell
& "$tool\AgentOrchestration\Test-CpvInstallerBundle.ps1" `
  -BundleRoot $bundleRoot `
  -ExpectedManifestSha256 $bundleManifestSha256 `
  -ExpectedSourceCommit 15320f410e43c7627d6e3ae61424ef20aa23d29e `
  -ExpectedRuntimeManifestSha256 B7077E707DD052AB7E233D6865824C90345D5629AA77CC750E7D34C29598AB32 `
  -ExpectedRollbackManifestSha256 7232FC5A028B4C5F6E3C3A9B5FD4831F94380AF135BC76046EF918D9A8B842F1 `
  -ExpectedToolCommit <reviewed-bundle-tool-commit>
```

The validator checks the manifest hash, source identity, exact file inventory, every file hash, both embedded release manifests, and the fixed fixture hash. The bundle scripts use Windows PowerShell 5.1 and the built-in `ScheduledTasks`, CIM, security, filesystem, and named-pipe APIs. No external PowerShell module is required.

The packaging and validation commands do not run installer, service, task, reconciliation, approval, preparation, or Revit operations. Their tests use temporary directories and the existing release roots only as read-only inputs.

## Production boundary

Do not run the installer as part of packaging. Production installation requires separate explicit authorization for the exact bundle manifest hash, runtime manifest hash, task/request identity, and elevated account. The failed-request exception is limited to request `9953e14c15524fe09440d1c7d7353950` and task `task-bf61fe7f22d74df7a92599681da5919e`; it preserves the active marker. Installation recovery uses `Recover-CpvPreparationAgentInstall.ps1` with those exact identities and the durable journal.

Invoke `Invoke-CpvPreparationRecovery.ps1` from an authenticated RepatoQA session with an explicit protected `-StoreRoot`; never use the bundle's default `QA\MayaRuns` path for the production task store. Fresh approval preparation requires the supported source checkout and its verified frozen-candidate evidence. Neither bundle validation nor successful installation constitutes native Revit QA evidence.
