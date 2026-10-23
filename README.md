# Terminal welcome page: native review captures

Source commit: [`028eb0e259f163a83fd108b5674d6b579dde1e84`](https://github.com/Aschenbath/pebrel/commit/028eb0e259f163a83fd108b5674d6b579dde1e84).
Feature: [Kuddev/pebrel#702](https://github.com/Kuddev/pebrel/issues/702).

These are Windows GPUI client captures from the opt-in `native_welcome_preview`
fixture, using isolated settings and 200% display scaling. Each fixture closes
its owned window and shuts down any terminal it starts. This branch contains
supplementary visual evidence; application and regression-test sources are in
the feature commit.

| Capture | State |
| --- | --- |
| [Dark English](welcome-dark-en.png) | Nord, 1000 × 720 logical pixels |
| [Light Chinese, narrow](welcome-light-zh-narrow.png) | Warm Sand, 460 × 400 logical pixel stress case |
| [Keyboard focus](welcome-keyboard-focus.png) | Tab focuses Local terminal and shows its ring |
| [Local hover](welcome-local-hover.png) | Actual pointer over Local terminal |
| [Local pressed](welcome-local-pressed.png) | Local terminal held down |
| [SSH hover](welcome-ssh-hover.png) | Actual pointer over Open SSH session |
| [SSH pressed](welcome-ssh-pressed.png) | SSH button held down |
| [SSH host list](ssh-host-list.png) | Existing host library reached from welcome |
| [Startup preference](terminal-startup-settings.png) | Chinese setting and expanded two-choice menu |

The narrow fixture deliberately goes below the application's regular window
minimum to stress layout. Hover and pressed states change the corresponding
button's pixels without moving its bounds. Actual local-shell creation was also
checked through Tab/Enter and a live PTY PID; these images do not establish SSH
authentication or remote connectivity.

## Reproduce on Windows

Check out the source commit and build the test executable:

```powershell
cargo test --locked -p nebula --bin pebrel --features gpui-test-support --no-run
```

From that checkout's root, run `capture.ps1` with the test executable path printed
by Cargo and a fresh directory under the checkout's `tmp` directory:

```powershell
& '<evidence directory>\capture.ps1' `
  -TestBinary '<Cargo test executable>' `
  -FixtureDir (Join-Path $PWD 'tmp\welcome-preview') `
  -Theme light -Language zh-CN -Narrow
```

Omit `-Narrow` for pointer states. `-State` accepts `focus`, `local`, `ssh`, `hover`,
`pressed`, `hover-ssh`, `pressed-ssh`, `settings`, and `settings-dropdown`.
The capture driver shows only its verified child window. For pointer captures,
it temporarily moves the pointer into that window and restores its position.
Images use the native client's `PrintWindow` output. Native fixture assertions
verify the selected theme and logical size before capture.
