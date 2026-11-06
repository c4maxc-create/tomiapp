Based on video_compress 3.1.4 from pub.dev; upstream LICENSE retained.

Android's original compressVideo passed selected duration as TrimDataSource's
end-discard duration. Full-length selections could therefore discard the whole
clip. TomiTrim converts start + selected duration to start/end discard in long
microseconds, clamped to actual source duration. It also avoids 32-bit overflow
when trimming late in a long source. Bare file paths become file:// URIs for the
native media APIs. Output names use UUIDs so quick retries cannot overwrite the
same output. The Dart processing flag resets in finally after platform failures.

The iOS/macOS trim semantics are unchanged. Check tool/check_video_trim.py and
Dart regression tests. A successful native build is not a hardware codec test.

Vendored text files have trailing whitespace normalized.
