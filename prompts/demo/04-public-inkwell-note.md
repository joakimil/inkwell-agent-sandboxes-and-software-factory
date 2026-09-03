# Ship a published, publicly visible note in the Inkwell app

Give Inkwell a real published note on first boot, so the anonymous public URL shows a finished blog
post instead of an empty page. The note is written by you (the builder) from the outline below — it
is a real, human-quality note, not lorem ipsum.

Why it matters: this sandbox exists so the world can open the public Inkwell URL and read a note
that was produced end to end by the machinery — coms handoff, the library skill, the pi harness,
the factory, the disposable VM. An empty home page would prove the loop ran but show nothing.

Where: apps/inkwell/server.ts (seed on db open), apps/inkwell/server.test.ts (new tests). No UI
change needed — the existing public home page already renders published posts to anonymous
visitors.

## The note to ship

Title: A note written by machines

Content (markdown, at least 350 words of real prose) built from this outline:

- Opening scene: one agent bolts a laptop to another by a wire of public keys and sockets — a
  message carried from one machine to the next over a coms channel, no email, no buzzing app.
- The stack behind that handoff: a shared skill library that makes both machines speak the same
  playbooks, a terminal multiplexer stacking half a dozen agents into one view, and a mesh that
  lets each machine reach the other by name as if they sat side by side.
- The factory: a deterministic loop that treats the build as a graph — plan, build, test, commit —
  with small specialized agents filling each phase and a cheap disposable key paying their bills.
- The punchline: the note you are reading is the payload. Machines wrote it, shipped it, published
  it, and exposed it on a public URL, and no human touched a keyboard between the handoff and now.

## Done means

1. On db open, when the posts table is empty, the app inserts exactly one post with the title and
   content above and status published. Existing rows are never touched, and a second boot never
   duplicates it.
2. The note is at least 350 words. A comment in the seed names the source prompt
   (prompts/demo/04-public-inkwell-note.md) so a reader can find where the words came from.
3. GET /api/posts returns it for anonymous requests with status published, and the public home page
   renders it.
4. The existing suite in apps/inkwell stays green (bun test), and new tests cover the seed: boot
   against an empty db and the note exists and is published; boot again with a row already present
   and nothing is duplicated.
5. git status --porcelain is clean after the commit.
