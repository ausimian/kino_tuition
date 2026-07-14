defmodule KinoTuition do
  @moduledoc """
  Render a [`tuition`](https://github.com/ausimian/tuition) terminal UI inside
  Livebook, over xterm.js.

  `tuition` is a pure-Erlang TUI framework whose renderer already emits ANSI and
  whose input parser already consumes raw bytes — the two halves of a terminal
  wire. `kino_tuition` bridges that wire to an xterm.js terminal running in a
  Livebook cell, so a tuition app can be driven from the browser with no tty.

  ## Usage

      KinoTuition.new(fn opts -> :tuition_demo.start(opts) end, cols: 100, rows: 30)

  The function you pass receives the options map to hand to a tuition host
  (`:tuition_demo.start/1`, `:tuition_shell.start/2`, …); `KinoTuition` has already
  merged in `backend: KinoTuition.Backend` and the `bridge:` pid, so the host
  opens the Livebook-backed terminal instead of a local one.

  ## Where the server side lives

  Everything server-side is in this library, by design:

    * `KinoTuition.Terminal` — the `Kino.JS.Live` widget (the browser channel);
    * `KinoTuition.Bridge` — the intermediate process that adapts Livebook's
      push/event model to `tuition_term`'s pull/blocking `read`;
    * `KinoTuition.Backend` — the `:tuition_term` backend, a thin forward to the
      bridge.

  It is **not** in `tuition`: that library has a hard zero-dependency,
  transport-agnostic constraint, and this is Kino-specific glue. It is **not** a
  separate library either: it has no use outside Livebook.
  """

  @doc """
  Build a terminal widget that runs a tuition session. See `KinoTuition.Terminal.new/2`.
  """
  @spec new((map() -> any()), keyword()) :: Kino.JS.Live.t()
  def new(run, opts \\ []), do: KinoTuition.Terminal.new(run, opts)
end
