# Working in this repository

Zipboy is a native macOS archive app in Swift: AppKit, Command Line Tools only, no package
dependencies. It unpacks an archive into a temporary workspace, shows it in an outline view with a
Quick Look inspector, and zips the workspace back up as it autosaves. The aim is an Apple-grade app:
few visible choices, nothing to manage.

## Commands

All automation goes through `scripts/task`; CI and the hooks call nothing else.

```sh
scripts/task check            # fmt:check, lint (warnings are errors), test, universal build
scripts/task test <name>      # one test or suite
scripts/task fmt              # swift format, in place
scripts/task package 0.2.0    # build/Zipboy-0.2.0.dmg, as a release ships it
```

## Where code goes

- `Sources/ZipboyKit`: everything that can be tested without a window. A behaviour change goes here
  with a test first.
- `Sources/Zipboy`: the app shell. `Sources/CArchive`: the libarchive declarations.
- Path-specific rules load from `.claude/rules/` when you touch those files. Procedures (releasing,
  fixtures, running the app for screenshots) are skills in `.claude/skills/`.

## Workflow

- Never commit to `main`. It advances only through a merged pull request; GitHub enforces it too.
- One unit of work, one worktree, one branch, one PR: `scripts/agent start fix/0042-the-thing`, then
  `scripts/agent commit`, `scripts/agent pr`, and `scripts/agent done` after the merge.
- Branch `<type>/<item>-<slug>`, type one of `feat fix chore docs perf refactor test`, item from cairn.
- `scripts/task check` must pass before a PR. The hooks enforce it; never `--no-verify`.
- Conventional Commits: imperative subject of at most 72 characters, no trailing period, the body says
  why, and a `Refs:` trailer with the cairn item's uid. Merges are squashes.
- A bug fix comes with the test that fails without it.
- No AI or assistant attribution in commits, PRs, comments, or docs.

<!-- cairn:begin -->
## Roadmap and issues

This project tracks its roadmap and issues with `cairn`. Every item is a Markdown file under `cairn/items`, described by the schema in `cairn.toml`.

**Do not create ad-hoc TODO, PLAN or NOTES files.** Create a cairn item instead, so the work appears on the board and in the generated roadmap.

### The loop

1. `cairn next` — what is ready to start. It excludes anything blocked by unfinished dependencies and puts work already in progress first.
2. `cairn claim <ID>` — take it before you start, so no one duplicates the work. `cairn claim --next` picks and claims the top-ranked unclaimed item in one step. Then read `cairn prompt <ID>`: the item with everything it rests on — the outcome it serves, what its dependencies concluded, what done means and what earlier runs learned.
3. Do the work. Record what you learn: `cairn set <ID> <field>=<value>` for fields, `cairn note <ID> "<TEXT>"` for anything that needs a sentence — why you chose something, what you tried, what to watch for.
4. `cairn tick <ID> <N>` as each acceptance criterion becomes true — `cairn show <ID> --criteria` lists them numbered. Tick what is true, not what would let you close.
5. `cairn close <ID>` when it is done, or `cairn release <ID>` to hand it back.
6. `cairn check` before you report finished. It must pass.

### Commands

```sh
cairn next --json                 # ready work, ranked
cairn claim --next                # take the next ready item
cairn search <TEXT> --json        # titles, bodies and labels
cairn list --json                 # all open items
cairn list --filter 'blocked=false,priority=p0'
cairn prompt <ID>                 # the item as a prompt, with what it rests on
cairn show <ID> --json            # one item, including its body
cairn new "<TITLE>" --type <TYPE> --milestone <MILESTONE>
cairn set <ID> status=<STATUS>    # also labels+=x, or any field below
cairn note <ID> "<TEXT>"          # append reasoning; never replaces
cairn show <ID> --criteria        # acceptance criteria, numbered
cairn tick <ID> <N>               # tick one; --all for every one
cairn close <ID>
cairn check                       # validate; run before finishing
cairn render                      # regenerate ROADMAP.md
```

Claims coordinate writers in the same item directory and are seen across the worktrees of this repository: `next` leaves out what another worktree has claimed, `claim` refuses it, and `cairn worktrees` shows what each is doing. Separate clones are not read. Agree on assignments before splitting work across clones.

Items are numbered: `0012`, and commands accept the bare number too. Write the number in `depends_on` and other id references. Each item also carries a `uid` tag; leave it alone. If a merge gives two items one number, `cairn renumber` moves the one that arrived and retargets the references that came with it.

### Schema

- **Types**: `feature`, `bug`, `chore`, `docs`, `spike`, `milestone`
- **Statuses**: `backlog` (open), `planned` (open), `doing` (active), `blocked` (active), `done` (done), `dropped` (dropped)
- **`due`**: date, YYYY-MM-DD — when a milestone is meant to land
- **`part_of`**: names any items, by id, several allowed — a larger piece of work this belongs to
- **`priority`**: one of p0, p1, p2, p3 — p0 is a release blocker
- **`effort`**: one of s, m, l, xl — Rough size, not an estimate
- **`area`**: one of archive, document, browser, preview, shell, system, distribution, quality — Subsystem this touches
- **Milestones**: `v0.1` (due 2026-11-20), `v0.2` (due 2026-12-18), `v0.3` (due 2027-01-29), `v0.4` (due 2027-03-12), `v1.0` (due 2027-04-23), `later`
- **Saved views** (`cairn list --view NAME`): `now`, `next`, `blockers`, `spikes`, `triage`

### Rules

1. Before starting work, find or create the item and set it to an active status.
2. Use the fields above rather than inventing new ones; add new fields to `cairn.toml` first.
3. Never hand-edit the generated roadmap file — change items and run `cairn render`.
4. `cairn check` must pass before the work is considered done.

<!-- cairn:end -->
