# Command ordering: native Windows review captures

These screenshots show the actual GPUI command manager from the source commit recorded beside each capture. The opt-in `native_command_order_preview` test loads synthetic commands in an isolated configuration directory and starts no terminal.

Windows desktop scaling: 200% (192 DPI). The normal fixtures use an 800 × 480 logical-pixel viewport. The 360 × 480 fixture deliberately goes below the normal product window minimum to check the command manager's narrow layout.

| Capture | What to inspect |
| --- | --- |
| [Dark folder list](review-root-dark-en/window.png) | Custom folder controls, disabled boundary directions, fixed built-in folder without ordering controls. |
| [Light command hover](review-folder-light-en/window.png) | Long name truncation with the full action area visible; 32px ordering targets. |
| [Chinese narrow command hover](review-folder-dark-zh-narrow/window.png) | A 360px native viewport with visible actions and readable, truncated content. |
| [Search results](review-search-dark-en/window.png) | Ordering controls are absent; normal result actions remain available. |
| [Keyboard boundary focus](review-focus-light-en/window.png) | The moved folder remains selected; focus stays in the control group when its downward move becomes disabled. |

The capture helper raises only the fixture-owned window, records its actual viewport, and captures only the client area. Hover captures use the real desktop pointer at the row bounds reported by GPUI. Every native test completed successfully after capture. Continuous keyboard movement, repeated Enter/Space at either boundary, Escape, concurrent store edits, persistence errors and search ranking are also covered by automated behavior tests.

The existing search placeholder remains Chinese in the English configuration; this feature adds localized ordering labels and does not change that pre-existing placeholder. These captures establish Windows visual behavior; they do not claim native visual acceptance on macOS or Linux.
