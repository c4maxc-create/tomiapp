package com.example.video_compress;

/** Convert selected start + duration to Transcoder's start/end discard values. */
public final class TomiTrim {
    private TomiTrim() {}
    public static long[] bounds(long totalMs, int startSeconds, Integer durationSeconds) {
        if (totalMs <= 0 || totalMs > Long.MAX_VALUE / 1000L || startSeconds < 0 ||
            (durationSeconds != null && durationSeconds <= 0)) {
            throw new IllegalArgumentException("Invalid trim interval");
        }
        long totalUs = totalMs * 1000L;
        long startUs = ((long) startSeconds) * 1000000L;
        if (startUs >= totalUs) throw new IllegalArgumentException("Trim starts after video");
        long endUs = durationSeconds == null ? totalUs :
            Math.min(totalUs, startUs + ((long) durationSeconds) * 1000000L);
        return new long[] { startUs, totalUs - endUs };
    }
}
