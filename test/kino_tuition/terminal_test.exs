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
end
