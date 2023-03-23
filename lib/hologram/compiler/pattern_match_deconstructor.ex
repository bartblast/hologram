defmodule Hologram.Compiler.PatternMatchDeconstructor do
  alias Hologram.Compiler.IR

  @doc """
  Deconstructs a pattern match IR into binding and literal value access paths.
  An access path specifies how a given element can be accessed in a nested data structure.
  The nodes in access paths are reversed, i.e. the first node is the deepest one.

  ## Examples

      iex> ir = IR.for_code("{1, b} = {a, 2}")
      iex> PatternMatchDeconstructor.deconstruct(ir)
      [
        [pattern_value: %IR.IntegerType{value: 1}, tuple_index: 0],
        [binding: :b, tuple_index: 1],
        [:expression_value, {:tuple_index, 0}],
        [:expression_value, {:tuple_index, 1}]
      ]
  """
  @spec deconstruct(IR.t(), nil | :pattern | :expression, list) :: list
  def deconstruct(ir, context \\ nil, path \\ [])

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

  def deconstruct(%IR.Symbol{name: name}, :pattern, path) do
    [[{:binding, name} | path]]
  end

  def deconstruct(%IR.TupleType{data: data}, side, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      tuple_index_path = [{:tuple_index, index} | path]
      acc ++ deconstruct(value, side, tuple_index_path)
    end)
  end

  def deconstruct(ir, :pattern, path) do
    [[{:pattern_value, ir} | path]]
  end

  def deconstruct(_ir, :expression, path) do
    [[:expression_value | path]]
  end
end
