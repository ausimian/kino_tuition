defmodule KinoTuition.Backend do
  @moduledoc """
  A `:tuition_term` backend that carries a tuition session over a Livebook
  `KinoTuition` widget instead of a local tty.

  `tuition` separates its renderer/input/widgets from the transport beneath them
  with the `:tuition_term` behaviour; a local raw-mode tty (`:tuition_term_local`)
  and a scripted test backend (`:tuition_loop_term`) are two interchangeable
  implementations. This is a third: every callback is a thin forward to the
  `KinoTuition.Bridge` handed in via the open options.

  A tuition host selects it exactly as it selects any backend — with
  `backend: KinoTuition.Backend` (and a `bridge:` pid) in the options map it
  passes to `:tuition_term.open/2`:

      :tuition_demo.start(%{backend: KinoTuition.Backend, bridge: bridge})

  `KinoTuition.Terminal` fills those two keys in for you. Nothing in the app above
  the backend seam is aware Livebook is involved.

  ## Capability probing over Livebook

  A tuition host that probes the terminal (e.g. `tuition_demo`, via
  `tuition_caps:probe/1`) writes device queries and reads the replies within a
  short (~100 ms) window. That window assumes a local tty; over Livebook the
  server→browser→xterm→server round-trip usually overruns it, so the probe times
  out (colours fall back to the 256-colour baseline) and xterm's replies arrive
  *after* the loop has started, as input. The `?`-private CSI answers (DA1,
  DECRQM, kitty-flags) are ignored by `tuition_input`, but the DECRQSS truecolor
  read-back is a DCS (`ESC P … ST`) that decodes as a burst of `Alt`-key events.

  This can't be fixed cleanly at the backend: a DCS shares its `ESC P` prefix with
  a genuine `Alt`+`Shift`+`P` keystroke, so the reply can't be stripped from the
  input stream unambiguously, and making `write/2` synchronous doesn't help (the
  browser round-trip is unacknowledged and the probe's timeout is the host's).
  Prefer a non-probing host for production — `tuition_shell` does not probe. The
  proper fix is an upstream hook to skip probing and inject xterm.js's known-fixed
  capabilities; tracked as a follow-up.
  """
  @behaviour :tuition_term

  @typedoc "Backend state: just the bridge every callback forwards to."
  @type state :: %{bridge: KinoTuition.Bridge.t()}

  @impl true
  def open(%{bridge: bridge}), do: {:ok, %{bridge: bridge}}
  def open(_opts), do: {:error, :no_bridge}

  @impl true
  def write(%{bridge: bridge}, data) do
    KinoTuition.Bridge.write(bridge, data)
    :ok
  end

  @impl true
  def read(%{bridge: bridge}, timeout), do: KinoTuition.Bridge.read(bridge, timeout)

  @impl true
  def size(%{bridge: bridge}), do: KinoTuition.Bridge.size(bridge)

  @impl true
  def close(_state), do: :ok
end
