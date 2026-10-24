# Fixtures

- `container.rar`: Homebrew's test fixture (BSD-2-Clause), from `Library/Homebrew/test/support/fixtures/cask/`.
- `encrypted-data.rar`, `encrypted-header.rar`: libarchive's `test_read_format_rar_encryption_data.rar` and
  `test_read_format_rar_encryption_header.rar` from v3.7.4 (BSD-2-Clause, Copyright Tim Kientzle and the
  libarchive contributors).
- `encrypted.7z`: `hello.txt` and `dir/world.txt`, made with `7zz a -t7z -psecret`.
- `matrix/`: one archive per variant Zipboy promises to read, checked by `FixtureMatrixTests`.
  `scripts/make-fixtures` regenerates all but the RAR files, which are libarchive's test files from v3.7.4
  (BSD-2-Clause, Copyright Tim Kientzle and the libarchive contributors): `rar4-normal.rar`
  (`test_read_format_rar_compress_normal`), `rar4-unicode.rar` (`…_rar_unicode`), and `rar5-*.rar`
  (`…_rar5_stored`, `…_compressed`, `…_solid`, `…_unicode`, `…_symlink`).
