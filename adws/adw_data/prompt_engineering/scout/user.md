# Scout Task

## Variables

### prompt

{{prompt}}

### previous_envelope

{{previous_envelope}}

### context_handoff_dir

{{context_handoff_dir}}

## Task

Find what `prompt` asks about. Write findings into `context_handoff_dir`, then emit your `Report` JSON.

## Task

Find what `prompt` asks about. Write findings into `context_handoff_dir`, then emit your `Report` JSON.

### Focus hint — start with the recent diff

Before you start reading the tree, orient on what has actually been moving. Two commands, run from the repo root:

```sh
git log --oneline -20
git diff HEAD~5..HEAD --stat   # widen HEAD~N until you see real activity, or shrink if too much
```

The first tells you what shipped recently. The second tells you which files are in flux. Both are signals the static tree cannot give you. A scout that knows which 3 files changed in the last 20 commits will spend its context on those, not on a 200-file traversal that mostly re-confirms what an old scout already found.

When `prompt` is open-ended ("survey the repo", "what is X"), this focus hint is the difference between a useful answer and a directory listing. When `prompt` is specific ("where is the timeout-guard extension"), skip it and go straight to the question — the diff won't help.

## Report

Respond with ONLY valid JSON matching `ScoutOutput` — no prose before or after:

```json
{
  "status": "success",
  "summary": "<one sentence on what you found>",
  "findings": [
    { "file": "src/server.ts", "note": "<why this file matters>" }
  ],
  "artifacts": ["<context_handoff_dir>/scout_findings.md"]
}
```
