---
name: fixtures
description: Add or regenerate the archive fixtures in Tests/ZipboyKitTests/Fixtures/matrix and keep FixtureMatrixTests in step. Use when supporting a new archive variant, changing what one contains, or when fixtures need regenerating.
---

# Archive fixtures

`scripts/make-fixtures` (stdlib Python, run with `uv`) writes every generated fixture; each holds
`hello.txt` ("hello\n") and `dir/world.txt` ("world\n"), password "secret" when encrypted. The RAR files
in the matrix are libarchive's and can't be regenerated: nothing free writes RAR.

1. Install the one tool it needs beyond macOS: `brew install sevenzip`.
2. Add the variant to `scripts/make-fixtures`, using bsdtar, zip, 7zz, or `zipfile` for ZIP quirks.
   Keep each fixture under 64 KB; an ISO is stored gzipped for that reason.
3. Run `scripts/make-fixtures`. It's safe to run again.
4. Add the file's expectation to `FixtureMatrixTests.cases`: `.opens(paths, password:)` or
   `.fails("words from the message")`. `everyFixtureHasACase` fails until you do.
5. For a vendored file, copy it in and credit it in `Tests/ZipboyKitTests/Fixtures/README.md`.
6. `scripts/task test FixtureMatrixTests`, then update the "What it opens" table in `README.md` if the
   promise changed.
7. Lint the script if you touched it: `uvx ruff check scripts/make-fixtures && uvx ruff format scripts/make-fixtures`.
