# Phase 3 bootstrap (not executed)

An authorized administrator will install the signed agent under the protected
`Program Files\Repato\QaLaunchAgent` directory, create the fixed policy file,
and register a RepatoQA-logon-only startup task whose sole action is the fixed
agent executable. The task will not accept request arguments.

The administrator will configure the RepatoQA account SID, orchestration client
SID, exact Revit path, disposable QA runtime root, manifest root, protected
replay/log directory, and pipe name. The pipe DACL will be verified before the
agent is started. A harmless synthetic handshake will be completed before any
Revit authorization. No password is collected or stored.
