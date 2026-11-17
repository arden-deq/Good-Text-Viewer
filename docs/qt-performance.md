# Large TXT test (1.1.0, macOS)

One Release-build run on Apple M3 Pro, macOS 27.0, Qt 6.8.3 (Cocoa). The test opens each local file in an already-running reader and measures until Qt renders the first page. It then clicks the far right of the progress bar and measures until Qt renders the end of the text. The preview does not wait for the complete background page index.

| Input | Bytes | First page | Early jump to end | Full page index |
| --- | ---: | ---: | ---: | ---: |
| [Norvig's public text corpus](https://www.norvig.com/spell-correct.html) | 6,488,666 | 100 ms | 51 ms | 1.62 s |
| [enwik8: English Wikipedia text](https://www.mattmahoney.net/dc/textdata.html) | 100,000,000 | 135 ms | 101 ms | 24.06 s |
| Local Korean CP949 novel | 268,039 | 38 ms | 59 ms | 98 ms |

The enwik8 input matched the publisher's SHA-1 (`57b8363b814821dc9d47aa4d41f58733519076b2`). After indexing, the same jump took 2 ms. These are single-run measurements, not timing guarantees or Windows results.

To reproduce after `make build`, provide local TXT files as a colon-separated list on macOS:

```sh
GTV_TEST_CORPUS="/path/to/big.txt:/path/to/enwik8.txt" \
  QT_QPA_PLATFORM=cocoa .build/qt-local/reader_tests externalCorpus
```

The Qt test checks that each file opens, reaches the end while the index is being built, completes the index, and shows 100% after the final jump. Test data is not included in the release archives.
