defmodule Hologram.Compiler.PatternMatching do
  alias Hologram.Compiler.IR

  @doc """
  Given reversed access paths from a deconstructed pattern match, it extracts pattern bindings access paths.

  ## Examples

      iex> reversed_access_paths = [
      ...>   [pattern_binding: :a, tuple_index: 0, list_index: 0],
      ...>   [
      ...>     pattern_literal: %IR.IntegerType{value: 1},
      ...>     tuple_index: 1,
      ...>     list_index: 0
      ...>   ],
      ...>   [
      ...>     pattern_binding: :b,
      ...>     map_key: %IR.AtomType{value: :b},
      ...>     tuple_index: 2,
      ...>     list_index: 0
      ...>   ],
      ...>   [
      ...>     :match_placeholder,
      ...>     {:map_key, %IR.AtomType{value: :c}},
      ...>     {:tuple_index, 2},
      ...>     {:list_index, 0}
      ...>   ],
      ...>   [
      ...>     pattern_literal: %IR.IntegerType{value: 2},
      ...>     map_key: %IR.AtomType{value: :d},
      ...>     tuple_index: 2,
      ...>     list_index: 0
      ...>   ],
      ...>   [pattern_binding: :b, tuple_index: 3, list_index: 0],
      ...>   [:match_placeholder, {:list_index, 0}, :list_tail],
      ...>   [{:pattern_binding, :f}, {:list_index, 1}, :list_tail],
      ...>   [:expression, {:list_index, 0}],
      ...>   [:expression, {:list_index, 1}],
      ...>   [:expression, {:list_index, 2}]
      ...> ]
      iex> aggregate_pattern_bindings(reversed_access_paths)
      %{
        a: [[list_index: 0, tuple_index: 0]],
        b: [
          [list_index: 0, tuple_index: 2, map_key: %IR.AtomType{value: :b}],
          [list_index: 0, tuple_index: 3]
        ],
        f: [[:list_tail, {:list_index, 1}]]
      }
  """
  @spec aggregate_pattern_bindings(list) :: %{atom => list}
  def aggregate_pattern_bindings(reversed_access_paths) do
    reversed_access_paths
    |> Enum.filter(&match?([{:pattern_binding, _} | _], &1))
    |> Enum.group_by(fn [{:pattern_binding, name} | _] -> name end)
    |> Enum.map(fn {name, binding_reversed_access_paths} ->
      {name,
       Enum.map(binding_reversed_access_paths, fn [{:pattern_binding, _} | tail] ->
         Enum.reverse(tail)
       end)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Given reversed access paths from a deconstructed pattern match, it extracts pattern literals access paths.

  ## Examples

      iex> reversed_access_paths = [
      ...>   [pattern_binding: :a, tuple_index: 0, list_index: 0],
      ...>   [
      ...>     pattern_literal: %IR.IntegerType{value: 1},
      ...>     tuple_index: 1,
      ...>     list_index: 0
      ...>   ],
      ...>   [
      ...>     pattern_binding: :b,
      ...>     map_key: %IR.AtomType{value: :b},
      ...>     tuple_index: 2,
      ...>     list_index: 0
      ...>   ],
      ...>   [
      ...>     :match_placeholder,
      ...>     {:map_key, %IR.AtomType{value: :c}},
      ...>     {:tuple_index, 2},
      ...>     {:list_index, 0}
      ...>   ],
      ...>   [
      ...>     pattern_literal: %IR.IntegerType{value: 2},
      ...>     map_key: %IR.AtomType{value: :d},
      ...>     tuple_index: 2,
      ...>     list_index: 0
      ...>   ],
      ...>   [pattern_binding: :b, tuple_index: 3, list_index: 0],
      ...>   [:match_placeholder, {:list_index, 0}, :list_tail],
      ...>   [{:pattern_binding, :f}, {:list_index, 1}, :list_tail],
      ...>   [:expression, {:list_index, 0}],
      ...>   [:expression, {:list_index, 1}],
      ...>   [:expression, {:list_index, 2}]
      ...> ]
      iex> aggregate_pattern_literals(reversed_access_paths)
      [
        [{:list_index, 0}, {:tuple_index, 1}, %IR.IntegerType{value: 1}],
        [
          {:list_index, 0},
          {:tuple_index, 2},
          {:map_key, %IR.AtomType{value: :d}},
          %IR.IntegerType{value: 2}
        ]
      ]
  """
  @spec aggregate_pattern_literals(list) :: list
  def aggregate_pattern_literals(reversed_access_paths) do
    reversed_access_paths
    |> Enum.filter(&match?([{:pattern_literal, _} | _], &1))
    |> Enum.map(fn [{:pattern_literal, value} | tail] ->
      Enum.reverse([value | tail])
    end)
  end

  @doc """
  Deconstructs a pattern match into pattern bindings, pattern literals and expressions access paths.
  An access path specifies how a given element can be accessed in a nested data structure.
  The nodes in access paths are reversed, i.e. the first node is the deepest one.

  ## Examples

      iex> ir = IR.for_code("{1, b} = {a, 2}")
      iex> deconstruct(ir)
      [
        [pattern_literal: %IR.IntegerType{value: 1}, tuple_index: 0],
        [pattern_binding: :b, tuple_index: 1],
        [:expression, {:tuple_index, 0}],
        [:expression, {:tuple_index, 1}]
      ]
  """
  @spec deconstruct(IR.t(), nil | :pattern | :expression, list) :: list
  def deconstruct(ir, side \\ nil, path \\ [])

  def deconstruct(%IR.BitstringType{segments: segments}, side, path) do
    segments
    |> Enum.reduce({[], []}, fn segment, {acc, offset} ->
      details =
        segment
        |> Map.take([:endianness, :signedness, :size, :type, :unit])
        |> Map.put(:offset, offset)

      bitstring_segment_path = [{:bitstring_segment, details} | path]

      new_acc = acc ++ deconstruct(segment.value, side, bitstring_segment_path)
      new_offset = [{segment.size, segment.unit} | offset]

      {new_acc, new_offset}
    end)
    |> elem(0)
  end

  def deconstruct(%IR.ConsOperator{head: head, tail: tail}, side, path) do
    head_path = [{:list_index, 0} | path]
    paths_nested_in_head = deconstruct(head, side, head_path)

    tail_path = [:list_tail | path]
    paths_nested_in_tail = deconstruct(tail, side, tail_path)

    paths_nested_in_head ++ paths_nested_in_tail
  end

  def deconstruct(%IR.ListType{data: data}, side, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      list_index_path = [{:list_index, index} | path]
      acc ++ deconstruct(value, side, list_index_path)
    end)
  end

  def deconstruct(%IR.MapType{data: data}, side, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      map_key_path = [{:map_key, key} | path]
      acc ++ deconstruct(value, side, map_key_path)
    end)
  end

  def deconstruct(%IR.MatchOperator{left: left_ir, right: right_ir}, :pattern, path) do
    left_paths = deconstruct(left_ir, :pattern, path)
    right_paths = deconstruct(right_ir, :pattern, path)

    left_paths ++ right_paths
  end

  def deconstruct(%IR.MatchOperator{left: left_ir, right: right_ir}, _side, path) do
    left_paths = deconstruct(left_ir, :pattern, path)
    right_paths = deconstruct(right_ir, :expression, path)

    left_paths ++ right_paths
  end

  def deconstruct(%IR.PinOperator{name: name}, :pattern, path) do
    [[{:variable, name} | path]]
  end

  def deconstruct(%IR.MatchPlaceholder{}, :pattern, path) do
    [[:match_placeholder | path]]
  end

  def deconstruct(%IR.TupleType{data: data}, side, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      tuple_index_path = [{:tuple_index, index} | path]
      acc ++ deconstruct(value, side, tuple_index_path)
    end)
  end

  def deconstruct(%IR.Variable{name: name}, :pattern, path) do
    [[{:pattern_binding, name} | path]]
  end

  def deconstruct(ir, :pattern, path) do
    [[{:pattern_literal, ir} | path]]
  end

  def deconstruct(_ir, :expression, path) do
    [[:expression | path]]
  end
end
