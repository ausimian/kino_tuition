### Added

- Initial release of `kino_tuition`, a Livebook (Kino) terminal widget that
  renders a [`tuition`](https://github.com/ausimian/tuition) TUI in the browser
  over xterm.js. Modules:
  - `KinoTuition` — the public entry point (`new/2`).
  - `KinoTuition.Terminal` — the `Kino.JS.Live` widget hosting an xterm.js
    terminal and driving a tuition session behind it.
  - `KinoTuition.Bridge` — the intermediate process adapting Livebook's
    push/event model to `tuition_term`'s pull/blocking `read`.
  - `KinoTuition.Backend` — a `:tuition_term` backend forwarding to the bridge, so
    a tuition host opens a Livebook-backed terminal with
    `backend: KinoTuition.Backend`.
- The browser terminal fits the notebook cell's width (xterm fit addon) and
  reports size changes back through the widget, so the tuition layout follows the
  on-screen geometry.
- Terminal capabilities are supplied, not probed. The widget injects a fixed
  profile for xterm.js — the assumed baseline plus truecolor — through tuition's
  `caps` option, so a probe-aware host (via `tuition_caps:resolve/2`) skips the
  interactive capability probe, which is unreliable over Livebook's async
  round-trip. This keeps 24-bit colour and stops the probe's late replies from
  leaking into input.
