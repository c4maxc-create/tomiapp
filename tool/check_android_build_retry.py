"""Verify real failure classification and bounded retry without network or waits."""
import sys
import unittest
from retry_android_build import build, transient_download

GATEWAY = """Execution failed for task ':gradle:compileKotlin'.
Could not download kotlin-compiler-embeddable-2.2.21.jar
Could not GET 'https://github.com/JetBrains/kotlin/releases/download/v2.2.21/kotlin-compiler-embeddable-2.2.21.jar'. Received status code 504 from server: Gateway Time-out
"""


class RetryTest(unittest.TestCase):
    def drive(self, results):
        calls, waits = [], []
        def run(command):
            calls.append(command.copy())
            return results[len(calls)-1]
        command=['flutter', 'build', 'apk', '--dart-define=TOMI_API_URL=https://example.test']
        code=build(command,run=run,pause=waits.append)
        self.assertTrue(all(c==command for c in calls))
        return code,len(calls),waits

    def test_exact_reported_kotlin_gateway_failure_recovers(self):
        self.assertEqual(self.drive([(1,GATEWAY),(0,'APK built')]),(0,2,[30]))

    def test_persistent_outage_stops_and_preserves_failure(self):
        self.assertEqual(self.drive([(1,GATEWAY)]*3),(1,3,[30,60]))

    def test_real_compile_and_auth_errors_are_not_retried(self):
        for text in ["e: file:///app/src/Main.kt:3: Unresolved reference", "app.dart:4:2: Error: Unknown class", "Could not GET https://example.test. Received status code 403", "Could not GET https://example.test. Received status code 404", GATEWAY+'\ne: file:///app/Main.kt:2: Unresolved reference', GATEWAY+'\nCould not GET https://repo.example: Received status code 403']:
            with self.subTest(text=text):
                self.assertEqual(self.drive([(7,text)]),(7,1,[]))

    def test_transient_download_codes_and_timeouts(self):
        for text in ['Could not GET https://repo.example: Read timed out', 'Could not HEAD https://repo.example: Connection reset', 'Could not download: Received status code 429', 'Could not GET https://repo.example: Received status code 503']:
            self.assertTrue(transient_download(text),text)
        self.assertFalse(transient_download('A UI test expected status code 504'))

    def test_success_runs_once(self):
        self.assertEqual(self.drive([(0,'done')]),(0,1,[]))

    def test_process_status_is_observed(self):
        from retry_android_build import execute
        self.assertEqual(execute([sys.executable,'-c',"print('compile error'); raise SystemExit(9)"]), (9,'compile error\n'))


if __name__=='__main__':
    unittest.main()
