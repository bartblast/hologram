defmodule Hologram.Commons.PLTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.PLT

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.Reflection

  @tmp_path Reflection.tmp_path()
  @dump_dir "#{@tmp_path}/#{__MODULE__}"
  @dump_file "#{@dump_dir}/test.plt"

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
    clean_dir(@dump_dir)
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

  describe "dump/2" do
    test "creates nested path dirs if they don't exist", %{plt: plt} do
      dump_dir = "#{@dump_dir}/nested_1/_nested_2/nested_3"
      dump_file = "#{dump_dir}/test.plt"

      assert dump(plt, dump_file) == plt
      assert File.exists?(dump_dir)
    end

    test "writes serialized items to the given file", %{plt: plt} do
      assert dump(plt, @dump_file) == plt

      items =
        @dump_file
        |> File.read!()
        |> SerializationUtils.deserialize()

      assert items == Enum.into(@items, %{})
    end
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
    dump(plt, @dump_file)

    plt_2 = start()

    assert load(plt_2, @dump_file) == plt_2
    assert get_all(plt_2) == Enum.into(@items, %{})
  end

  describe "maybe_load/2" do
    test "dump file exists" do
      data =
        @items
        |> Enum.into(%{})
        |> SerializationUtils.serialize()

      File.write!(@dump_file, data)

      plt = start()
      assert maybe_load(plt, @dump_file) == plt

      assert get_all(plt) == Enum.into(@items, %{})
    end

    test "dump file doesn't exist" do
      plt = start()
      assert maybe_load(plt, @dump_file) == plt

      assert get_all(plt) == %{}
    end
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

  describe "start/1" do
    test "unnamed table" do
      assert %PLT{pid: pid, table_ref: table_ref, table_name: nil} = start()

      assert is_pid(pid)
      assert is_reference(table_ref)

      assert ets_table_exists?(table_ref)

      ets_info = :ets.info(table_ref)
      refute ets_info[:named_table]
      assert ets_info[:protection]
    end

    test "named table" do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      table_name = :"#{inspect(make_ref())}"

      assert %PLT{pid: pid, table_ref: table_ref, table_name: ^table_name} =
               start(table_name: table_name)

      assert is_pid(pid)
      assert is_reference(table_ref)

      assert ets_table_exists?(table_ref)
      assert ets_table_exists?(table_name)
      assert :ets.whereis(table_name)

      ets_info = :ets.info(table_ref)
      assert ets_info[:named_table]
      assert ets_info[:protection]
    end
  end
end
