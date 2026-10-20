# Installed Productivity Tools

This workspace contains local productivity and development support tools. They
help with planning, code assistance, and task automation; they do not replace
the Revit add-in or authorize Revit QA.

| Tool | Workspace location | Intended use |
| --- | --- | --- |
| Agent | `.agent/` | Project instructions, agent definitions, hooks, skills, and Get Shit Done (GSD) workflows for supported coding agents. |
| Claude Code | `.claude/` | Claude Code project configuration, hooks, skills, and GSD workflows. |
| Codex | `.codex/` | Codex project configuration, hooks, commands, agents, and GSD workflows. Keep its security settings unchanged unless explicitly authorized. |
| Gemini CLI | `.gemini/` | Gemini CLI project configuration, agent definitions, skills, and GSD workflows. |
| GitHub Copilot | `.github/` | Copilot project instructions and GSD skills for use in GitHub tooling. |
| Ralph | `.ralph/` | Local Ralph pilot prompt and run outputs for iterative productivity tasks. Its security settings must remain unchanged unless explicitly authorized. |
| Agent orchestration scripts | `AgentOrchestration/` | Local task tracking, validated workflow transitions, action previews, and adapter records. Documentation describes the supported operations and their approval boundaries. |

## Use and safety

- Choose the tool that matches the coding environment you are using, and follow
  the project instructions in `AGENTS.md` and that tool's configuration.
- GSD workflows are opt-in; Copilot project instructions say to use them only
  when specifically requested.
- Tool configuration and workflow support do not grant approval to run agents,
  build or deploy add-ins, or execute Revit QA. Follow the repository's
  authorization and safety requirements before those actions.
- Treat `.ralph/` run files as local task records. Do not change security
  settings as part of routine productivity work.

## Review after a Ralph iteration

Review only the files Ralph changed, or pass an explicit Git range. From the
workspace root:

```powershell
pwsh -NoProfile -File .\productivity-test\code-review\Invoke-LocalCodeReview.ps1 -Path @('.\ChangedFile.cs', '.\Folder With Space\ChangedFile.ps1')
pwsh -NoProfile -File .\productivity-test\code-review\Invoke-LocalCodeReview.ps1 -DiffRange 'BASE_SHA..HEAD'
```

See [the local code review guide](code-review/README.md) for result meanings
and regression tests. An automated PASS never authorizes merge or deployment.
