defmodule Hologram.Test.ComponentCaseTest do
  use Hologram.Test.ComponentCase, async: false

  import Mox

  # Stands in for the process of an earlier test that set Mox to global mode, whose exit Mox hasn't
  # handled yet.
  setup_all do
    test_pid = self()

    owner_pid =
      spawn(fn ->
        set_mox_global()
        send(test_pid, :mox_global_set)
        Process.sleep(:infinity)
      end)

    on_exit(fn -> Process.exit(owner_pid, :kill) end)

    assert_receive :mox_global_set, 1_000

    :ok
  end

  test "starts in Mox private mode while an earlier test's global owner is still alive" do
    stub(AssetPathRegistryMock, :static_dir, fn -> "/my_static_dir" end)

    assert AssetPathRegistryMock.static_dir() == "/my_static_dir"
  end
end
