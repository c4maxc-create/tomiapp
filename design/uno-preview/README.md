# TOMI Card Club — interactive motion reference

Original browser-based design study accompanying `unity/TomiUno`. It does not replace Flutter and does not connect to production. All names, levels, cards, timers and effects are demo values. No coins, XP, purchases or server turns change.

Run from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory design/uno-preview
node --test design/uno-preview/model.test.mjs
# With the local server running and Python Playwright + Chromium installed:
python3 design/uno-preview/browser_check.py
```

Use the browser to open the local server. A generated `standalone.html` also opens directly from disk, with all CSS and JavaScript included. No fonts, image assets or network services are required. Select cards, play, draw, choose a wild color, toggle UNO, replay the deal or sample special effects. The model deliberately permits any card so every animation is reachable; actual eligibility remains on the TOMI server.

Reduced motion follows the OS preference and can be toggled. Color choice supports keyboard traversal and Escape. The hand uses partially overlapping cards; click an exposed edge to select a covered card.

Checks performed in Chromium at 1440, 390 and 320 pixels: selection, play, draw, wild-color choice, reduced-motion re-deal, no page-level horizontal overflow and no JavaScript exceptions. Model tests cover invalid wild colors, unowned/repeated actions, unique IDs, reset isolation and bounded draw state. This validates the browser reference only, not Unity compilation or phone rendering.
