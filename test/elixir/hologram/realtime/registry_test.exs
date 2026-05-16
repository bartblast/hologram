defmodule Hologram.Realtime.RegistryTest do
  use Hologram.Test.BasicCase, async: false

  alias Hologram.Realtime.Registry

  setup do
    wait_for_process_cleanup(Registry)
    start_supervised!(Registry)

    :ok
  end

  test "starts under a supervisor and registers itself by module name" do
    assert process_name_registered?(Registry)
  end

  test "creates the backing ETS table with the documented name and options" do
    table_name = Registry.ets_table_name()

    assert table_name == :hologram_subscriptions
    assert ets_table_name_registered?(table_name)

    info = :ets.info(table_name)

    assert info[:type] == :set
    assert info[:protection] == :public
    assert info[:named_table] == true
    assert info[:read_concurrency] == true
  end
end
