defmodule KinoTuition.BackendTest do
  use ExUnit.Case, async: true

  alias KinoTuition.Backend
  alias KinoTuition.Bridge

  test "drives the :tuition_term contract through a bridge" do
    {:ok, bridge} = Bridge.start_link(output: self(), size: {90, 30})
    {:ok, state} = Backend.open(%{bridge: bridge})

    assert {:ok, {90, 30}} = Backend.size(state)

    assert :ok = Backend.write(state, "hello")
    assert_receive {:stdout, "hello"}

    Bridge.input(bridge, "k")
    assert {:ok, "k"} = Backend.read(state, 100)

    assert :timeout = Backend.read(state, 10)
    assert :ok = Backend.close(state)
  end

  test "open without a bridge errors" do
    assert {:error, :no_bridge} = Backend.open(%{})
  end

  test "KinoTuition.Backend is a :tuition_term behaviour module" do
    # The behaviour is declared, so the compiler enforced all five callbacks.
    assert :tuition_term in (KinoTuition.Backend.module_info(:attributes)[:behaviour] || [])
  end
end
