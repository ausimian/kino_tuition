defmodule KinoTuition.Bridge do
  @moduledoc """
  The intermediate process that adapts Livebook's push model to `tuition_term`'s
  pull model.

  `tuition`'s terminal-backend behaviour (`:tuition_term`) is **pull-based**: the
  render/input loop calls `read/2` — which blocks up to a timeout waiting for
  input — and polls `size/1` each frame. A Kino widget is **push-based**: xterm.js
  pushes keystrokes and resize events into the `Kino.JS.Live` server
  asynchronously, whenever the user acts.

  This `GenServer` sits between the two and reconciles them:

    * **input** pushed from the browser is buffered here; a blocking `read/2` is
      answered immediately if bytes are waiting, otherwise it is *parked* until
      input arrives or its timeout fires — so the loop sees a normal blocking tty;
    * **size** pushed from the browser is stored and returned to `size/1` polls;
    * **output** (rendered ANSI) written by the loop is forwarded to the widget
      process, which relays it to the browser.

  It is the same shape as the `reader`/`sizer` helpers `tuition_loop_term` spawns
  for its scripted test backend — but fed live from the browser instead of a
  canned script. It is Kino-specific glue and so lives here, in `kino_tuition`,
  not in transport-agnostic `tuition`.
  """
  use GenServer

  @typedoc "A running bridge process."
  @type t :: pid()

  # A parked read is capped at this many ms even when the caller asked for
  # `:infinity`, so the loop periodically unblocks to re-poll size / repaint.
  @infinity_read_cap 60_000

  ## ------------------------------------------------------------------
  ## Client API — push side, called from the Kino.JS.Live widget process
  ## ------------------------------------------------------------------

  @doc "Start a bridge. Options: `:output` (pid to send `{:stdout, bin}` to, required), `:size`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Buffer input bytes pushed from the browser (xterm.js `onData`)."
  @spec input(t(), iodata()) :: :ok
  def input(bridge, data), do: GenServer.cast(bridge, {:input, IO.iodata_to_binary(data)})

  @doc "Record a new terminal size pushed from the browser (xterm.js `onResize`)."
  @spec resize(t(), {pos_integer(), pos_integer()}) :: :ok
  def resize(bridge, {cols, rows}), do: GenServer.cast(bridge, {:resize, {cols, rows}})

  ## ------------------------------------------------------------------
  ## Backend API — pull side, called from the tuition loop via KinoTuition.Backend
  ## ------------------------------------------------------------------

  @doc """
  Blocking read: return any buffered bytes, else wait up to `timeout` ms for some,
  answering `:timeout` if none arrive. Mirrors `:tuition_term.read/2`.
  """
  @spec read(t(), timeout()) :: {:ok, binary()} | :timeout
  def read(bridge, timeout) do
    # The server arms its own timer and always replies within `timeout`, so the
    # call waits indefinitely for that reply rather than racing it.
    GenServer.call(bridge, {:read, timeout}, :infinity)
  end

  @doc "The latest terminal size reported by the browser."
  @spec size(t()) :: {:ok, {pos_integer(), pos_integer()}}
  def size(bridge), do: GenServer.call(bridge, :size)

  @doc "Forward rendered ANSI out to the widget process (relayed to the browser)."
  @spec write(t(), iodata()) :: :ok
  def write(bridge, iodata), do: GenServer.cast(bridge, {:write, IO.iodata_to_binary(iodata)})

  ## ------------------------------------------------------------------
  ## Server
  ## ------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      output: Keyword.fetch!(opts, :output),
      size: Keyword.get(opts, :size, {80, 24}),
      # Bytes pushed from the browser but not yet handed to a read.
      buffer: <<>>,
      # `{from, timer_ref}` while a read is parked awaiting input, else nil.
      waiter: nil
    }

    {:ok, state}
  end

  @impl true
  # Bytes already buffered: satisfy the read at once.
  def handle_call({:read, _timeout}, _from, %{buffer: buf} = state) when buf != <<>> do
    {:reply, {:ok, buf}, %{state | buffer: <<>>}}
  end

  # A read is somehow already parked (the single-threaded loop should never do
  # this): answer the newcomer with a timeout rather than dropping the parked one.
  def handle_call({:read, _timeout}, _from, %{waiter: {_, _}} = state) do
    {:reply, :timeout, state}
  end

  # No bytes and no parked read: park this one and arm a timer to answer `:timeout`.
  def handle_call({:read, timeout}, from, %{waiter: nil} = state) do
    ref = Process.send_after(self(), {:read_timeout, from}, cap_timeout(timeout))
    {:noreply, %{state | waiter: {from, ref}}}
  end

  def handle_call(:size, _from, state) do
    {:reply, {:ok, state.size}, state}
  end

  @impl true
  def handle_cast({:input, data}, %{waiter: nil} = state) do
    {:noreply, %{state | buffer: state.buffer <> data}}
  end

  # Input for a parked reader: cancel its timer and hand it the bytes now.
  def handle_cast({:input, data}, %{waiter: {from, ref}} = state) do
    Process.cancel_timer(ref)
    GenServer.reply(from, {:ok, state.buffer <> data})
    {:noreply, %{state | buffer: <<>>, waiter: nil}}
  end

  def handle_cast({:resize, size}, state) do
    {:noreply, %{state | size: size}}
  end

  def handle_cast({:write, data}, state) do
    send(state.output, {:stdout, data})
    {:noreply, state}
  end

  @impl true
  def handle_info({:read_timeout, from}, %{waiter: {from, _ref}} = state) do
    GenServer.reply(from, :timeout)
    {:noreply, %{state | waiter: nil}}
  end

  # A timer that fired after its read was already satisfied by input — ignore.
  def handle_info({:read_timeout, _from}, state) do
    {:noreply, state}
  end

  defp cap_timeout(:infinity), do: @infinity_read_cap
  defp cap_timeout(t) when is_integer(t) and t >= 0, do: t
  defp cap_timeout(_), do: 0
end
