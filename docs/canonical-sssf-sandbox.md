# Canonical SSSF in a Sandbox — Working, and How

> **Status: verified green end-to-end.** A throwaway exe.dev VM clones the
> *private* canonical Super Simple Software Factory, provisions itself, and runs
> ADWs whose formula changes are confirmed live. This doc is the map of what
> works and the mechanics that make it work.

Last verified: fresh VM `sssf-canon-test-04657`, canonical `example@dd1f5a7`,
orchestrator `main@31777ed`.

---

## TL;DR

The sandbox now fills from the **canonical SSSF** (`joakimil/super-simple-software-factory`,
branch `example`) instead of a self-contained copy. That repo is **private** and
is **pure payload** — no provisioning scaffolding of its own. Two mechanics close
that gap:

1. **Deploy-key clone** — the host hands the VM a read-only SSH deploy key so it
   can read a private repo with no interactive auth.
2. **Guest-scaffolding injection** — the orchestrator pushes its own
   `sandbox_mount/guest/` (provision.sh + models.json.tmpl) into the clone before
   provisioning, and hides it from the git-integrity gate.

On top of that, `adw_document` now **auto-resolves `--base`**, so it works on a
sandbox clone that has no local `main`.

---

## The two-repo split (why this was non-trivial)

There are two repositories, and they are **not** the same thing:

| Repo | Role | Ships provisioning? | Visualizer? |
|---|---|---|---|
| `super-simple-software-factory` (`example`) | **Payload** — the factory + a demo blog app | No | No |
| `inkwell-agent-sandboxes-and-software-factory` (`main`) | **Orchestrator** — the six-phase VM lifecycle | Yes (`sandbox_mount/guest/`) | Yes |

The old fill cloned the *orchestrator* into the VM, so `provision.sh` happened to
be inside the clone. Redirecting fill to the *canonical payload* broke that
assumption: the payload has no `sandbox_mount/`, no `provision.sh`, no visualizer.

**The fix follows the layering:** the orchestrator *owns* provisioning and
*injects* it into whatever payload it mounts. The canonical stays a clean payload.

---

## Mechanic 1 — Deploy-key clone of a private repo

`just/sandbox/lifecycle/fill.just`

```
REPO="git@github.com:joakimil/super-simple-software-factory.git"   # SSH form
BRANCH="example"                                                    # SHA arg still wins
DEPLOY_KEY_PATH="${SSSF_DEPLOY_KEY:-$HOME/.ssh/sssf/deploy}"
```

Before the clone, the host (which holds the key) provisions the VM:

```
scp  $DEPLOY_KEY_PATH            → VM:~/.ssh/id_sssf      (chmod 600)
ssh  ssh-keyscan github.com     >> VM:~/.ssh/known_hosts  (dedup, no TOFU prompt)
```

The remote clone then runs with the key pinned:

```
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_sssf -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
git clone --branch example git@github.com:joakimil/super-simple-software-factory.git app
```

**Deploy key:** `sssf-fill-deploy`, ed25519, **read-only**, registered on both the
canonical and the orchestrator repo. The VM only ever *reads* — it never pushes;
the host harvests results via a git bundle over scp, so read-only is sufficient.

Why not anonymous HTTPS? The repo is private → `git clone https://…` prompts for a
username, and a TTY-less VM cannot answer, so it dies with
`could not read Username for 'https://github.com'`. Why not the VM's own SSH key?
exe.dev VMs have no key registered on GitHub. A per-fill deploy key is the least
privilege that works.

---

## Mechanic 2 — Guest-scaffolding injection

`just/sandbox/lifecycle/setup.just`, phase 1/3, before `provision.sh`:

```
ssh  VM 'mkdir -p app/sandbox_mount/guest'
scp  sandbox_mount/guest/{provision.sh,models.json.tmpl} → VM:app/sandbox_mount/guest/
ssh  VM 'cd app && echo /sandbox_mount/ >> .git/info/exclude'   # local-only ignore
```

- `provision.sh` derives its repo root from its own path (`../..`), so dropping it
  at `app/sandbox_mount/guest/provision.sh` makes it provision `~/app` correctly.
- The **`.git/info/exclude`** line is load-bearing: gate A ("git integrity")
  demands a clean worktree, and the injected `sandbox_mount/` would otherwise show
  as `?? sandbox_mount/` and fail the mount. Excluding it is safe — it is
  orchestrator scaffolding, never payload, and real ADW output lands in
  `adws/`, `apps/`, `app_docs/`, never there. It touches the clone's local
  exclude only, never the tracked `.gitignore`.
- Payload-specific provision steps (`apps/inkwell` bun install, visualizer build)
  are already guarded by `-f`/`-d` and **skip cleanly** when the canonical lacks
  them.

---

## Mechanic 3 — `adw_document` auto-resolves `--base`

`adws/adw_modules/changes.py :: default_base()` (canonical repo)

Hardcoding `--base main` broke on any clone without a **local** `main`. A sandbox
fills from `--branch example`, so the run branch `sbx/<id>` has only `example`
locally, and `git diff main` died on a missing ref. Resolution order of intent:

1. local `main` / `master` — a normal dev checkout; measure against trunk.
2. the sole other local branch — a sandbox run forked from its fill branch
   (e.g. `example`); that branch is exactly the fork point.
3. `origin/HEAD` — a clone with no useful local branch.
4. `HEAD~1` / `HEAD` — last resort so "document what was just done" still answers.

`adw_document --base` now defaults to `None` and resolves through this. An
explicit `--base` still wins and still errors on a bad ref. Verified: unqualified
`adw_document` in the sandbox auto-picked `example`.

---

## The formula changes, verified live

Three payload changes were the point of the test. All three confirmed running in
the VM:

| Formula (canonical `example`) | What it does | Evidence in the VM |
|---|---|---|
| `tracer.py` — `duration_ms` | per-phase wall-clock in the `phases` table | column present; `scout` row = **30472 ms** ↔ the 30.5 s the UI showed |
| `scout/user.md` — focus hint | scout opens with `git log`/`git diff` recon before tree traversal | scout made real `git log --oneline -20` **tool calls** (not just prompt text) |
| `documenter/user.md` — `git add` | stage the `app_docs/` writeup so harvest sees it | `git status` shows `A  app_docs/<id>_*.md` (staged, not `??`) |

---

## Reproduce it

```bash
# on the host (macmini), from the orchestrator repo
just sbx mount <run-id>          # create → fill (deploy-key clone) → setup (inject + gate)

# then, inside the VM
ssh <run-id>.exe.xyz
cd ~/app
uv run adws/adw_scout.py    --config adws/adw_sssf_config/sssf.config.yaml "…question…"
uv run adws/adw_document.py --config adws/adw_sssf_config/sssf.config.yaml "…topic…"   # no --base needed

# tear down when done
just sbx lifecycle teardown <run-id>
```

Prereqs on the host: the deploy key at `~/.ssh/sssf/deploy` (or `SSSF_DEPLOY_KEY`),
registered read-only on the canonical repo.

---

## Full lifecycle at a glance

```
create   mint runtime key + boot VM
fill     scp deploy key → clone canonical(example) over SSH → write .env
setup    inject guest/ → run provision.sh → 5-assertion health gate
observe  start app + visualizer, expose ports
run      drive ADWs (scout / plan / build / document …)
harvest  bundle the run branch → scp to host (VM never pushes)
teardown destroy the VM
```

Everything above `fill`/`setup` is unchanged; those two phases carry the whole
private-canonical adaptation.
