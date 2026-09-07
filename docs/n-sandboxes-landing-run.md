# N Sandboxes, N Landing Pages — A Working Run

> **Status: verified working.** Three isolated exe.dev VMs each cloned the private
> canonical SSSF, provisioned themselves, and ran a `plan-build` ADW **in parallel**
> — all writing the *same* file with *different* design briefs. Three distinct
> landing pages came out; nothing crossed between runs.

Run date: 2026-09-07. Canonical `example@05a77da`, orchestrator `main` (+ fixes below).

---

## What was demonstrated

The point of N sandboxes is **parallel, isolated variation**: fan one task out
across many VMs, let each explore independently, compare the results. This run
made that concrete.

- **Task (identical target):** create `apps/inkwell/public/jj-workout.html`, a
  standalone landing page for a workout-tracking app.
- **Three briefs (different intent):** bold/high-energy, minimal/premium,
  dark/data-driven.
- **Three VMs, fired detached, all running at once.**

| Arm | Design brief | adw_id | commit | cost | Headline it produced |
|---|---|---|---|---|---|
| bold | orange→red, high-energy | `aa58385c` | `19069ab` | $0.73 | *Train Hard. Track Harder.* |
| minimal | monochrome premium | `52a18977` | `9a2cd35` | $0.25 | *Track your strength with quiet precision.* |
| dark | cyan/lime data dashboard | `b543a45b` | `e1c104c` | $0.41 | *Data-Driven Training* |

Palette fingerprints confirmed each stayed on-brief:
`bold #ff0044/#ff8844` · `minimal #fbfbfd/#f2f2f7` · `dark #a3e635/#64748b on slate`.
Sizes tracked intent too: minimal leanest (13 KB), dark richest (33 KB).

Outputs saved to `~/Desktop/jj-workout-landings/` on the host; each was also live
at `https://<vm>.exe.xyz/jj-workout.html` (HTTP 200) until teardown.

Total spend across all three arms: **~$1.39**.

---

## The flow, end to end

```
just sbx mount <arm>                      # ×3: create → fill (deploy-key clone) → setup → observe
just sbx lifecycle execute <arm> "<brief>" "" plan-build   # ×3, detached, parallel
# … builders work concurrently on 3 separate VMs …
just sbx lifecycle teardown <arm> --no-harvest             # ×3: shred key, close record, destroy
```

Each `execute` returns a PID and streams to the VM's `run.log`; the workflow was
`plan-build` (planner → builder → commit), deliberately chosen over full `sdlc`
because a static HTML page has no test suite to satisfy.

---

## Three seams found and fixed (all payload/orchestrator boundary issues)

Running the *canonical* payload through the *inkwell* orchestrator exposed three
places where the orchestrator still assumed the old self-contained payload. All
are the same class of bug as the deploy-key / guest-injection work, and all now
fixed.

1. **`execute.just` called `just adw <workflow>`.**
   The old inkwell payload exposed workflows under a just module (`just adw sdlc`);
   the canonical exposes them at top level (`just sdlc`, `just plan-build`).
   **Fix:** dropped the `adw` prefix in the remote invocation (orchestrator, committed).

2. **Roster referenced an unresolvable model id.**
   Both rosters used `fireworks/accounts/fireworks/models/kimi-k3`, but
   `models.json` registers it as `moonshotai/kimi-k3`. Config validation rejected
   it, so `plan-build`/`sdlc` died before the planner ran (scout had survived only
   because it uses `google/gemini-3.6-flash`).
   **Fix:** corrected the id in both rosters (canonical `05a77da`, pushed).

3. **`harvest` bundle can't verify against the host.**
   `git bundle` uses the canonical base commit (`dd1f5a7`) as a prerequisite, but
   the host's harvest repo is the *orchestrator* (inkwell), which shares no history
   with the canonical payload — so `git bundle verify` fails. **Not yet fixed**;
   worked around with `teardown --no-harvest` since the artifacts were already
   pulled. The proper fix is for harvest to bundle self-contained (`--all` with no
   external prerequisite) or to verify against the payload origin, not the host.
   Tracked as follow-up.

---

## The isolation guarantee, observed

The **bold** arm failed on its first attempt — and that was the safety rails
working, not a defect. A manual hot-patch had left `adws/adw_sssf_config/sssf.config.yaml`
uncommitted; the builder is barred from that path; the permission enforcer detected
the dirty barred path, **reverted it, and aborted the run** before any further work.
Committing the fix on the run branch let the arm proceed to success. Containment
did exactly what it promises: an agent cannot quietly mutate the machinery it runs
inside.

---

## Teardown

All four VMs (three arms + the earlier canonical smoke-test) were destroyed
cleanly: runtime key file shredded, run record closed, and the post-condition gate
confirmed each key was **absent** from the OpenRouter key list. No VMs or keys left
behind.

---

## Follow-ups

- **Fix harvest for the canonical payload** (seam #3) so run history can be
  persisted, not just the built files.
- The roster still carries a few models that are invalid or rate-limited on this
  gateway (`gpt-5.6-luna` rate-limited, etc.); worth an audit against
  `pi --list-models` so every roster entry resolves.
