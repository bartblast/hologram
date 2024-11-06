defmodule Hologram.Commons.ETSTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.ETS

  setup do
    table_ref = create_unnamed_table()
    :ets.insert(table_ref, {:my_key_1, :my_value_1})
    :ets.insert(table_ref, {:my_key_2, :my_value_2})

    [table_ref: table_ref]
  end

  test "create_named_table/1" do
    table_name = random_atom()
    table_ref = create_named_table(table_name)

    assert is_reference(table_ref)
    assert ets_table_exists?(table_ref)
    assert ets_table_exists?(table_name)
    assert ets_table_name_registered?(table_name)

    ets_info = :ets.info(table_ref)
    assert ets_info[:named_table]
    assert ets_info[:protection] == :public
  end

  test "create_unnamed_table/1", %{table_ref: table_ref} do
    assert is_reference(table_ref)
    assert ets_table_exists?(table_ref)

    ets_info = :ets.info(table_ref)
    refute ets_info[:named_table]
    assert ets_info[:protection] == :public
  end

  describe "delete/1" do
    test "table exists" do
      table_ref = create_unnamed_table()

      assert delete(table_ref) == true
      refute table_exists?(table_ref)
    end

    test "table doesn't exist" do
      assert delete(make_ref()) == false
    end
  end

  describe "delete!/1" do
    test "table exists" do
      table_ref = create_unnamed_table()

      assert delete!(table_ref) == true
      refute table_exists?(table_ref)
    end

    test "table doesn't exist" do
      assert_raise ArgumentError, fn -> delete!(random_atom()) end
    end
  end

  describe "delete/2" do
    test "key exists", %{table_ref: table_ref} do
      assert delete(table_ref, :my_key_2) == true

      assert :ets.lookup(table_ref, :my_key_1) == [{:my_key_1, :my_value_1}]
      assert :ets.lookup(table_ref, :my_key_2) == []
    end

    test "key doesn't exist", %{table_ref: table_ref} do
      assert delete(table_ref, :my_key_3) == true

      assert :ets.lookup(table_ref, :my_key_1) == [{:my_key_1, :my_value_1}]
      assert :ets.lookup(table_ref, :my_key_2) == [{:my_key_2, :my_value_2}]
    end
  end

  describe "get/2" do
    test "key exists", %{table_ref: table_ref} do
      assert get(table_ref, :my_key_2) == {:ok, :my_value_2}
    end

    test "key doesn't exist", %{table_ref: table_ref} do
      assert get(table_ref, :my_key_3) == :error
    end
  end

  describe "get!/2" do
    test "key exists", %{table_ref: table_ref} do
      assert get!(table_ref, :my_key_2) == :my_value_2
    end

    test "key doesn't exist", %{table_ref: table_ref} do
      assert_raise KeyError, "key :my_key_3 not found in the ETS table", fn ->
        get!(table_ref, :my_key_3)
      end
    end
  end

  test "get_all/1", %{table_ref: table_ref} do
    assert get_all(table_ref) == %{my_key_1: :my_value_1, my_key_2: :my_value_2}
  end

  test "put/2", %{table_ref: table_ref} do
    items = [
      {:my_key_3, :my_value_3},
      {:my_key_4, :my_value_4}
    ]

    assert put(table_ref, items) == true

    assert get_all(table_ref) == %{
             my_key_1: :my_value_1,
             my_key_2: :my_value_2,
             my_key_3: :my_value_3,
             my_key_4: :my_value_4
           }
  end

  test "put/3", %{table_ref: table_ref} do
    assert put(table_ref, :my_key_3, :my_value_3) == true
    assert :ets.lookup(table_ref, :my_key_3) == [{:my_key_3, :my_value_3}]
  end

  test "reset/1", %{table_ref: table_ref} do
    assert reset(table_ref) == true
    assert get_all(table_ref) == %{}
  end

  describe "table_exists?/1" do
    test "exists, named" do
      table_name = random_atom()
      create_named_table(table_name)

      assert table_exists?(table_name)
    end

    test "exists, unnamed" do
      table_ref = create_unnamed_table()

      assert table_exists?(table_ref)
    end

    test "doesn't exist, named" do
      table_name = random_atom()

      refute table_exists?(table_name)
    end

    test "doesn't exist, unnamed" do
      refute table_exists?(make_ref())
    end
  end
end
