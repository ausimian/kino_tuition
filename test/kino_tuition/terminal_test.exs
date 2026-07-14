defmodule KinoTuition.TerminalTest do
  use ExUnit.Case, async: true

  import Kino.Test

  setup :configure_livebook_bridge

  # A run function that never returns, so the session (if started) just idles —
  # these tests exercise the widget's event handling, not a tuition loop.
  defp idle_run, do: fn _opts -> Process.sleep(:infinity) end

  test "connect returns the configured initial size" do
    kino = KinoTuition.new(idle_run(), cols: 100, rows: 30)
    assert connect(kino) == %{cols: 100, rows: 30}
  end

  test "a resize event updates the size a later connect reports" do
    kino = KinoTuition.new(idle_run(), cols: 80, rows: 24)
    assert connect(kino) == %{cols: 80, rows: 24}

    # The browser fits the terminal and pushes its real geometry.
    push_event(kino, "resize", %{"cols" => 132, "rows" => 43})

    # A newly connecting client now sees the resized geometry, and so does the
    # tuition loop via the bridge's size/1.
    assert connect(kino) == %{cols: 132, rows: 43}
  end

  test "once the session is owned, a non-owning client's resize is ignored" do
    kino = KinoTuition.new(idle_run(), cols: 80, rows: 24)

    # This test process becomes the owner: it connects and starts the session.
    connect(kino)
    push_event(kino, "ready", %{})

    # The owner's own resize is honoured.
    push_event(kino, "resize", %{"cols" => 100, "rows" => 30})
    assert connect(kino) == %{cols: 100, rows: 30}

    # A second client (a distinct process => a distinct Kino event origin) pushes
    # a different size, then reads the geometry back over its own synchronous
    # connect so the assertion sees the server state after its resize was handled.
    # The size stays the owner's 100x30 — the secondary resize was dropped.
    other =
      Task.async(fn ->
        push_event(kino, "resize", %{"cols" => 200, "rows" => 50})
        connect(kino)
      end)

    assert Task.await(other) == %{cols: 100, rows: 30}
  end

  test "the started session is handed a fixed xterm.js caps profile, not a probe" do
    test = self()
    run = fn opts -> send(test, {:started, opts}) end

    kino = KinoTuition.new(run)
    connect(kino)
    push_event(kino, "ready", %{})

    assert_receive {:started, opts}
    assert opts.backend == KinoTuition.Backend

    # The host is handed the xterm.js profile verbatim (baseline + truecolor), so
    # tuition_caps:resolve/2 uses it instead of writing an interactive probe.
    assert opts.caps == :tuition_caps.apply_colorterm(~c"truecolor", :tuition_caps.baseline())
    # ...and it genuinely enables truecolor over the bare baseline.
    refute opts.caps == :tuition_caps.baseline()
  end
end
