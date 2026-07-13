# KinoTuition

A [Livebook](https://livebook.dev) ([Kino](https://hexdocs.pm/kino)) terminal
widget that renders a [`tuition`](https://github.com/ausimian/tuition) TUI in the
browser over [xterm.js](https://xtermjs.org).

`tuition` is a pure-Erlang terminal UI framework. Its renderer
(`tuition_render:diff/2`) already emits ANSI, and its input parser
(`tuition_input`) already consumes raw bytes — the two halves of a terminal wire.
`kino_tuition` bridges that wire to an xterm.js terminal in a Livebook cell, so a
tuition app runs in the browser with no tty.

## Usage

In a Livebook cell:

```elixir
Mix.install([
  {:kino_tuition, github: "ausimian/kino_tuition"}
])
```

```elixir
KinoTuition.new(fn opts -> :tuition_demo.start(opts) end, cols: 100, rows: 30)
```

The function you pass is handed the options map for a tuition host
(`:tuition_demo.start/1`, `:tuition_shell.start/2`, …). `kino_tuition` has already
merged in `backend: KinoTuition.Backend` and the `bridge:` pid, so the host opens
the Livebook-backed terminal instead of a local one — nothing in the app above
tuition's backend seam is aware Livebook is involved.

## Architecture

```
 xterm.js (browser)             KinoTuition.Terminal           KinoTuition.Bridge         tuition loop
 ------------------             (Kino.JS.Live server)          (push <-> pull)            (via KinoTuition.Backend)
 onData  ─pushEvent"stdin"────►  handle_event("stdin") ─input─►  buffer ──── read/2 ─────►  key events
 onResize ─pushEvent"resize"──►  handle_event("resize")─resize►  size   ──── size/1 ──────►  layout
 term.write ◄─handleEvent──────  broadcast_event"stdout" ◄{:stdout}─ write/2 ◄─── ANSI ───── render diff
```

The clean fit is because both ends already speak an ANSI byte stream:
`tuition_render:diff/2` produces exactly what `term.write` consumes, and
`tuition_input` consumes exactly what `term.onData` produces. No PTY, no
translation layer.

### The one real impedance mismatch

`tuition_term` is **pull-based**: the loop calls `read/2` (blocking up to a
timeout) and polls `size/1`. Kino is **push-based**: the browser pushes events
into the `Kino.JS.Live` server whenever the user acts. `KinoTuition.Bridge`
reconciles them — it buffers pushed input and hands it to blocking reads (parking
a read until input arrives or its timeout fires), holds the latest pushed size for
polls, and forwards written ANSI out to the widget. It is the same shape as the
`reader`/`sizer` helpers `tuition_loop_term` spawns for its scripted test backend,
but fed live from the browser.

### Where the server side lives, and why

All three server-side pieces are in **this** library:

| Piece | Role |
| --- | --- |
| `KinoTuition.Terminal` | the `Kino.JS.Live` widget — the browser channel |
| `KinoTuition.Bridge`   | the intermediate process — the push↔pull adapter |
| `KinoTuition.Backend`  | the `:tuition_term` backend — a thin forward to the bridge |

- **Not in `tuition`.** `tuition` has a hard zero-dependency, transport-agnostic
  constraint (its whole point is embedding with no Elixir in the chain). Kino and
  Livebook are Elixir dependencies; this glue must not leak into the core.
- **Not a separate library.** The bridge has no use outside Livebook — it exists
  solely to adapt Livebook's transport to `tuition_term`. Splitting it out is
  premature.

`tuition` supplies only the `:tuition_term` behaviour contract and the
render/input/widget/shell stack; the app loop is the caller's.

## Status and known limitations

This is an initial cut. Working: a live tuition session streamed to a connected
client, keystrokes and rendered frames both directions, backend + bridge covered
by tests. Follow-ups:

- **Reconnect / late join.** The session starts on the first client's `"ready"`
  event, so that client sees the full first frame. A client that joins mid-session
  will not get a repaint until the next full frame. A robust fix keeps a
  server-side shadow of the screen (or forces a full repaint on connect).
- **Dynamic resize.** Geometry is fixed at the configured `cols`×`rows`. Wiring
  the xterm fit addon to the `"resize"` event the server already handles is a
  follow-up. On resize, `tuition_render` expects a fresh blank buffer (full
  repaint), since a diff assumes both buffers share geometry.
- **Capabilities.** `tuition_caps` probes the terminal (DA/DSR); xterm.js answers
  the standard queries, but handing tuition a fixed capability profile for the
  xterm.js backend would be more predictable than round-tripping probes.
- **Asset loading.** xterm.js is loaded from a CDN via Livebook's mediated
  `importJS`/`importCSS`. If your Livebook's CSP forbids that, vendor the assets
  and point the URLs at local copies.
- **Publishing.** `tuition` is consumed as a Git dependency (it is not yet on Hex),
  so `kino_tuition` cannot be published to Hex until it is. `Mix.install/2`
  resolves the Git dependency transitively, so notebook use is unaffected.

## License

Apache-2.0. See [LICENSE](LICENSE).
