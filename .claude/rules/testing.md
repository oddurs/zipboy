---
paths:
  - "Tests/**"
---

# Tests

- One test, or a suite: `scripts/task test <name>` (it adds the flags Command Line Tools need).
- A bug fix comes with the test that fails without it. Run it before the fix and say what it printed.
- Archive variants live in `Fixtures/matrix`, each with a case in `FixtureMatrixTests.cases`;
  `everyFixtureHasACase` fails otherwise. Regenerate with the `fixtures` skill, never by hand.
- `DocumentTests` and `SaveTests` drive `ArchiveDocument` directly. Start a save with `begin`, edit, then
  `finish`: a `Task` on the main actor would run after the edit. Group undo steps by hand
  (`groupsByEvent = false`), since a test has no event loop to group them.
- Don't depend on tools a stock Mac or the CI runner lacks (7zz, zstd); check fixtures in instead.
