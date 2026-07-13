defmodule KinoTuition.Terminal do
  @moduledoc """
  The Livebook terminal widget: a `Kino.JS.Live` component that hosts an xterm.js
  terminal in the browser and drives a `tuition` session behind it.

  ## How it fits together

      xterm.js (browser)              KinoTuition.Terminal            KinoTuition.Bridge        tuition loop
      ------------------              (Kino.JS.Live server)           (push<->pull)             (KinoTuition.Backend)
      onData  --pushEvent("stdin")-->  handle_event("stdin") --input-->  buffer ----read/2----->  key events
      onResize -pushEvent("resize")->  handle_event("resize")--resize-->  size  ----size/1------>  layout
      term.write <-handleEvent-------  broadcast_event("stdout") <-{:stdout}- write/2 <--ANSI---- render diff

  The whole server side lives in `kino_tuition`: this widget process, the
  `KinoTuition.Bridge` it starts, and the `KinoTuition.Backend` the loop talks
  through. `tuition` stays transport-agnostic.

  ## Lifecycle

  The tuition session is started lazily, on the first `"ready"` event a connected
  client sends *after* its terminal exists — so the loop's first (full) frame is
  delivered to a client that can display it, rather than broadcast into the void
  before any terminal is open.
  """
  use Kino.JS
  use Kino.JS.Live

  alias KinoTuition.Bridge

  @default_cols 80
  @default_rows 24

  @doc """
  Build a terminal widget that runs `run`.

  `run` is a 1-arity function that starts a tuition host, given the options map to
  pass it. `KinoTuition` merges `backend:` and `bridge:` into that map, so a
  typical `run` just forwards it to a tuition entrypoint:

      KinoTuition.Terminal.new(fn opts -> :tuition_demo.start(opts) end)

  Options:

    * `:cols` — initial terminal width in columns (default `#{@default_cols}`)
    * `:rows` — initial terminal height in rows (default `#{@default_rows}`)
  """
  @spec new((map() -> any()), keyword()) :: Kino.JS.Live.t()
  def new(run, opts \\ []) when is_function(run, 1) do
    cols = Keyword.get(opts, :cols, @default_cols)
    rows = Keyword.get(opts, :rows, @default_rows)
    Kino.JS.Live.new(__MODULE__, %{run: run, cols: cols, rows: rows})
  end

  @impl true
  def init(%{run: run, cols: cols, rows: rows}, ctx) do
    {:ok, bridge} = Bridge.start_link(output: self(), size: {cols, rows})

    {:ok, assign(ctx, run: run, bridge: bridge, cols: cols, rows: rows, started: false)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, %{cols: ctx.assigns.cols, rows: ctx.assigns.rows}, ctx}
  end

  @impl true
  def handle_event("ready", _payload, ctx) do
    {:noreply, maybe_start(ctx)}
  end

  def handle_event("stdin", data, ctx) do
    Bridge.input(ctx.assigns.bridge, data)
    {:noreply, ctx}
  end

  def handle_event("resize", %{"cols" => cols, "rows" => rows}, ctx) do
    Bridge.resize(ctx.assigns.bridge, {cols, rows})
    {:noreply, assign(ctx, cols: cols, rows: rows)}
  end

  @impl true
  def handle_info({:stdout, ansi}, ctx) do
    broadcast_event(ctx, "stdout", ansi)
    {:noreply, ctx}
  end

  def handle_info({:session_done, result}, ctx) do
    broadcast_event(ctx, "stdout", "\r\n[tuition session ended: #{inspect(result)}]\r\n")
    {:noreply, ctx}
  end

  # Start the tuition loop exactly once. It runs in its own unlinked process so a
  # session that crashes reports back instead of taking the widget down with it.
  defp maybe_start(%{assigns: %{started: true}} = ctx), do: ctx

  defp maybe_start(ctx) do
    %{run: run, bridge: bridge} = ctx.assigns
    parent = self()

    spawn(fn ->
      opts = %{backend: KinoTuition.Backend, bridge: bridge}

      result =
        try do
          run.(opts)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(parent, {:session_done, result})
    end)

    assign(ctx, started: true)
  end

  asset "main.js" do
    """
    export async function init(ctx, data) {
      // Load xterm.js and the fit addon on demand. `importJS`/`importCSS` are
      // Livebook's mediated loaders; if your Livebook's CSP forbids the CDN,
      // vendor these assets and point the URLs at local copies instead.
      await ctx.importCSS("https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css");
      await ctx.importJS("https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js");
      await ctx.importJS("https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js");

      // The UMD builds attach their constructors to the widget's window.
      const term = new window.Terminal({
        cols: data.cols,
        rows: data.rows,
        fontFamily: "monospace",
        cursorBlink: true,
        // tuition drives the cursor with absolute positioning; don't let xterm
        // rewrite the byte stream.
        convertEol: false
      });

      const fitAddon = new window.FitAddon.FitAddon();
      term.loadAddon(fitAddon);
      term.open(ctx.root);
      term.focus();

      // Fit the terminal to the cell's width, then report the real geometry so
      // the server lays its first frame out for the size actually on screen.
      // `fit()` only fires `onResize` when the grid changes, so report the
      // initial size explicitly to cover the no-change case too.
      fitAddon.fit();
      ctx.pushEvent("resize", { cols: term.cols, rows: term.rows });

      // Browser -> server.
      term.onData((bytes) => ctx.pushEvent("stdin", bytes));
      // A later fit (on cell resize) changes the grid and fires this; the server
      // updates its size, and tuition repaints into the new geometry.
      term.onResize(({ cols, rows }) => ctx.pushEvent("resize", { cols, rows }));

      // Server -> browser: write rendered ANSI straight to the terminal.
      ctx.handleEvent("stdout", (ansi) => term.write(ansi));

      // Re-fit (debounced) whenever the cell's width changes.
      let pending;
      const observer = new ResizeObserver(() => {
        clearTimeout(pending);
        pending = setTimeout(() => fitAddon.fit(), 100);
      });
      observer.observe(ctx.root);

      // The terminal exists and its size is reported; let the server start the
      // session (once) now that a client can display its first frame.
      ctx.pushEvent("ready", {});
    }
    """
  end
end
