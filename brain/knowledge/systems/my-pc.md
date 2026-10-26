---
about: "The owner's Windows PC: how agents reach it (the my-pc runner), the folder layout in C:/AI-Brain-Link, and what's on it. Read for facts about the PC; how to run a job is the my-pc skill."
tags: [the-brain]
updated: {KIT_DATE}
---
# The owner's PC

The PC is a GitHub Actions self-hosted runner for this brain's repo, labelled `my-pc` (and `gpu` with an NVIDIA card), running as a Windows service under the owner's own account. The installer set it up; `skills/my-pc/setup-runner.ps1` sets it up again. **How to run a job on it** is the [my-pc skill](../../skills/my-pc/SKILL.md). `skills/my-pc/check-setup.ps1` checks the whole setup and changes nothing; with `-Send` its report also lands on this shelf, as `setup-check.md`.

## Folder layout
```
C:\AI-Brain-Link\
  _runner\        the Actions runner (its checkouts go in _runner\_work\)
  _logs\          pc-run output, one UTF-16 log per run
  Tools\          shared tools, and watch-jobs.ps1 (the live jobs window)
  <repo name>\    the owner's copy of this brain, opened in Obsidian
  <Project>\<Stage>\<job>\   a job's data, made when a job first needs it
```

## What's on the PC
*Not checked yet: the getting-started skill fills this in from a first job on the PC.*
