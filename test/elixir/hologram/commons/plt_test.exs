defmodule Hologram.Commons.PLTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.PLT

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.Reflection

  @dump_path Reflection.tmp_path() <> "/plt_#{__MODULE__}.bin"

  @items [
    {:my_key_1, :my_value_1},
    {:my_key_2, :my_value_2}
  ]

  defp ets_table_exists?(table_ref) do
    table_ref
    |> :ets.info()
    |> is_list()
  end

  setup do
    File.rm(@dump_path)
    [plt: put(start(), @items)]
  end

  describe "delete/2" do
    test "key exists", %{plt: plt} do
      assert delete(plt, :my_key_2) == plt
      assert get(plt, :my_key_2) == :error
    end

    test "key doesn't exist", %{plt: plt} do
      assert delete(plt, :my_key_3) == plt
      assert get(plt, :my_key_3) == :error
    end
  end

  test "dump/2", %{plt: plt} do
    assert dump(plt, @dump_path) == plt

    items =
      @dump_path
      |> File.read!()
      |> SerializationUtils.deserialize()

    assert items == Enum.into(@items, %{})
  end

  describe "get/2" do
    test "key exists", %{plt: plt} do
      assert get(plt, :my_key_2) == {:ok, :my_value_2}
    end

    test "key doesn't exist", %{plt: plt} do
      assert get(plt, :my_key_3) == :error
    end
  end

  describe "get!/2" do
    test "key exists", %{plt: plt} do
      assert get!(plt, :my_key_2) == :my_value_2
    end

    test "key doesn't exist", %{plt: plt} do
      assert_raise KeyError, "key :my_key_3 not found in the PLT", fn ->
        get!(plt, :my_key_3)
      end
    end
  end

  test "get_all/1", %{plt: plt} do
    assert get_all(plt) == Enum.into(@items, %{})
  end

  test "load/2", %{plt: plt} do
    dump(plt, @dump_path)

    plt_2 = start()
    assert load(plt_2, @dump_path) == plt_2
    assert get_all(plt_2) == Enum.into(@items, %{})
  end

  test "put/2" do
    plt = start()
    assert put(plt, @items) == plt

    assert get(plt, :my_key_1) == {:ok, :my_value_1}
    assert get(plt, :my_key_2) == {:ok, :my_value_2}
  end

  describe "put/3" do
    test "first arg is a PLT struct", %{plt: plt} do
      assert put(plt, :my_key_3, :my_value_3) == plt
      assert get(plt, :my_key_3) == {:ok, :my_value_3}
    end

    test "first arg is an ETS table ref", %{plt: plt} do
      assert put(plt.table_ref, :my_key_3, :my_value_3) == true
      assert get(plt, :my_key_3) == {:ok, :my_value_3}
    end
  end

  test "start/0" do
    assert %PLT{pid: pid, table_ref: table_ref} = start()

    assert is_pid(pid)
    assert is_reference(table_ref)

    assert ets_table_exists?(table_ref)
  end
end
