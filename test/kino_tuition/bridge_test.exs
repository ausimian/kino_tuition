defmodule KinoTuition.BridgeTest do
  use ExUnit.Case, async: true

  alias KinoTuition.Bridge

  setup do
    {:ok, bridge} = Bridge.start_link(output: self(), size: {80, 24})
    %{bridge: bridge}
  end

  describe "read / input (the push -> pull adapter)" do
    test "already-buffered input is returned immediately", %{bridge: bridge} do
      Bridge.input(bridge, "abc")
      assert {:ok, "abc"} = Bridge.read(bridge, 100)
    end

    test "a read parks until input arrives, then returns it", %{bridge: bridge} do
      task = Task.async(fn -> Bridge.read(bridge, 1_000) end)
      # Let the reader park before any input is pushed.
      Process.sleep(20)
      Bridge.input(bridge, "x")
      assert {:ok, "x"} = Task.await(task)
    end

    test "a read with no input returns :timeout", %{bridge: bridge} do
      assert :timeout = Bridge.read(bridge, 20)
    end

    test "input accumulates across pushes until the next read", %{bridge: bridge} do
      Bridge.input(bridge, "ab")
      Bridge.input(bridge, "cd")
      assert {:ok, "abcd"} = Bridge.read(bridge, 100)
    end

    test "iodata input is flattened to a binary", %{bridge: bridge} do
      Bridge.input(bridge, ["a", ?b, ["c"]])
      assert {:ok, "abc"} = Bridge.read(bridge, 100)
    end

    test "a read after a prior read drained the buffer parks again", %{bridge: bridge} do
      Bridge.input(bridge, "first")
      assert {:ok, "first"} = Bridge.read(bridge, 100)
      assert :timeout = Bridge.read(bridge, 20)
    end
  end

  describe "size / resize" do
    test "size returns the initial size", %{bridge: bridge} do
      assert {:ok, {80, 24}} = Bridge.size(bridge)
    end

    test "resize updates what size returns", %{bridge: bridge} do
      Bridge.resize(bridge, {120, 40})
      assert {:ok, {120, 40}} = Bridge.size(bridge)
    end
  end

  describe "write" do
    test "forwards flattened ANSI to the output process", %{bridge: bridge} do
      Bridge.write(bridge, ["\e[2J", "hi"])
      assert_receive {:stdout, "\e[2Jhi"}
    end
  end
end
