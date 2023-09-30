defmodule Hologram.Commons.ETSTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.ETS

  test "create_named_table/1" do
    table_name = random_atom()
    table_ref = create_named_table(table_name)

    assert is_reference(table_ref)
    assert ets_table_exists?(table_ref)
    assert ets_table_exists?(table_name)
    assert :ets.whereis(table_name)

    ets_info = :ets.info(table_ref)
    assert ets_info[:named_table]
    assert ets_info[:protection] == :public
  end
end
