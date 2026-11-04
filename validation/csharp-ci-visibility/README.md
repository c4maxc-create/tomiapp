Hidden C# tab CI regression fix

Reproduced the four failures shown in GitHub run 41915855842: two accounts widget tests and two social layout tests timed out in pumpAndSettle. IndexedStack built the hidden C# page, whose loading indicator kept scheduling frames while native startup awaited I/O.

The page now starts its native host once, when first visible, and renders no loading animation before the hidden tab is opened. Existing tests and assertions were preserved. Added a focused IndexedStack regression test.

Validation: full Flutter suite 263 passed, 10 opt-in integration tests skipped; accounts/social subset 12 passed; hidden-tab regression passed; Flutter analyze no issues. Android APK build has not been run in this workspace. Start a NEW Android workflow on main after this commit; re-running an old run uses the old source.
