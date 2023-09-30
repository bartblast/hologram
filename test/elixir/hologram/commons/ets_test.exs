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

  test "create_unnamed_table/1" do
    table_ref = create_unnamed_table()

    assert is_reference(table_ref)
    assert ets_table_exists?(table_ref)

    ets_info = :ets.info(table_ref)
    refute ets_info[:named_table]
    assert ets_info[:protection] == :public
  end

  describe "get/2" do
    test "key exists, get from named table" do
      table_name = random_atom()
      create_named_table(table_name)
      put(table_name, :my_key, :my_value)

      assert get(table_name, :my_key) == {:ok, :my_value}
    end

    test "key exists, get from unnamed table" do
      table_ref = create_unnamed_table()
      put(table_ref, :my_key, :my_value)

      assert get(table_ref, :my_key) == {:ok, :my_value}
    end

    test "key doesn't exist, get from named table" do
      table_name = random_atom()
      create_named_table(table_name)

      assert get(table_name, :my_non_existing_key) == :error
    end

    test "key doesn't exist, get from unnamed table" do
      table_ref = create_unnamed_table()

      assert get(table_ref, :my_non_existing_key) == :error
    end
  end

  describe "put/3" do
    test "put to named table" do
      table_name = random_atom()
      create_named_table(table_name)

      assert put(table_name, :my_key, :my_value) == true
      assert :ets.lookup(table_name, :my_key) == [{:my_key, :my_value}]
    end

    test "put to unnamed table" do
      table_ref = create_unnamed_table()

      assert put(table_ref, :my_key, :my_value) == true
      assert :ets.lookup(table_ref, :my_key) == [{:my_key, :my_value}]
    end
  end
end
