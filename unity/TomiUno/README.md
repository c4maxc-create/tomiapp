> Five-game Unity/C# preview suite: see [ALL-GAMES-PREVIEW-AR.md](ALL-GAMES-PREVIEW-AR.md). Use TOMI → Open all-games preview, then Play. WebGL export is provided through TOMI → Build all-games WebGL preview. Unity Editor compilation, Play Mode and export have NOT been executed here; no runnable WebGL build or APK is claimed.

> Native Unity design update, 3 November 2026: the reference composition now uses a cyan sky, green floating island, rim stones/trees, native vector card orbits/action glyphs and real front/back reveal during deal/draw. These changes are C# in this project. They have NOT been compiled or rendered in Unity Editor here, and have NOT been embedded in the Flutter APK. No browser preview was used as proof of this update. Open the scene in Unity to assess the actual appearance, clipping, performance and animation.

# TOMI UNO — first motion prototype

Original jade felt / champagne rim / ivory card design. This is a separate Unity **design sandbox**, not a replacement for the current Flutter game. No APK, native Flutter bridge, live multiplayer, paid assets, or Unity runtime has been added to the shipping app.

## Open and run

1. Install Unity Hub and **Unity 6 LTS 6000.0.62f1**, with Android Build Support only if testing an Android standalone build. Unity licensing and device builds happen on your development machine.
2. Add this directory (`unity/TomiUno`) as a project in Hub. Let Unity import its declared packages.
3. Choose **TOMI → Create UNO preview scene**. Save any existing unsaved scene if prompted.
4. Press Play, with a landscape Game view such as 1920×1080 or 844×390. The scene builds the felt table, rim, cards, HUD and materials procedurally; there are no external art dependencies.
5. Try DEAL AGAIN, select and PLAY CARD, DRAW, UNO, special-effect buttons, wild color selection and REDUCE MOTION. The demo intentionally permits any selected card: it is a motion sandbox, not a local copy of server rules.
6. Use **Window → General → Test Runner → EditMode** for `SnapshotGateTests`.

The runtime scene initializer can also launch the prototype from an empty scene. This standalone prototype requests landscape orientation. Production embedding must negotiate orientation with Flutter and restore it when leaving the game.

## What's implemented

- A physical table mesh, wood-tone rail, gold trim and jade felt with directional lighting.
- Procedural rounded, ivory-edged card faces and backs; a seven-card hand.
- Staggered deal, curved card flights, selected-card lift, drawn cards, hand relayout, floating action labels and a wild-color selector.
- Deterministic example cards, bounded demo hand, re-deal and reduced-motion timing.
- A plain JSON snapshot DTO matching existing TOMI field names, a stale-reply gate, own-hand eligibility checks and an action-intent event for future host integration.
- The separate browser motion study at `design/uno-preview` has a more finished Arabic presentation and responsive portrait layout. It is a **visual reference**, not output rendered by Unity. The two views are not claimed to be pixel-identical.

## Transport boundary — future integration, NOT connected yet

`UnoTablePreview.designSandbox` defaults to true in the Inspector. Keep it true for this design phase. With it false, `ApplyServerSnapshot(json)` can render a validated hand and discard; `ActionRequested` emits an intent with requestId and revision. `RetryPending()` emits that same object. `ResolvePending(requestId)` must be called by the host for the matching accepted receipt or definitive rejection. `ClearSession()` clears private hand and pending state; the snapshot gate requires a clear before changing match identity.

This is a starting boundary, **not a finished network client**: the host still must authenticate, check match/session ownership, persist pending intents durably, map the real API envelope, handle definitive vs uncertain failures, refresh server state, measure server-clock offset and provide spectator-safe opponent counts/names. The demo seats and timer presentation are placeholders. Never treat the intent event as a successful move or award coins/XP from an animation.

Keep existing server game rules, private-card filtering, wallets, receipts and XP authoritative. Do not move random draws or win calculations to Unity. Do not put server API keys or persistent auth tokens in scene assets. Prefer short-lived scoped host messages rather than copying a long-lived Flutter session into Unity.

## Remaining production work

- Validate project compilation and run EditMode/PlayMode tests in Unity Editor (not available in the current cloud runtime).
- Match the browser art direction in actual Unity assets/shaders, add real opponent turn/count states, accepted-snapshot animations, gestures, audio and localization with proper Arabic shaping (the initial Unity HUD uses English).
- Choose and verify a maintained Flutter/Unity embedding approach, lifecycle and audio-focus behavior. No embedding dependency was guessed or added here.
- Profile on actual mid-range Android phones; test app/background/resume, room/call audio, accessibility, memory, GPU/CPU time and app-size increase.
- Only then wire the production API and build a device APK. No FPS, native audio continuity, live multiplayer or APK success is claimed by this prototype.
