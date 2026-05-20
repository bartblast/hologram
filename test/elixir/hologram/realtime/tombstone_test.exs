defmodule Hologram.Realtime.TombstoneTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Tombstone

  alias Hologram.Realtime.Tombstone

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Tombstone)
    start_supervised!(Tombstone)

    :ok
  end

  describe "start_link/1" do
    test "starts under a supervisor and registers itself by module name" do
      assert process_name_registered?(Tombstone)
    end

    test "creates the backing ETS table" do
      assert :ets.info(ets_table_name()) != :undefined
    end
  end
end
