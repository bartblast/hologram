defmodule Hologram.Compiler.PatternMatching do
  alias Hologram.Compiler.IR

  def deconstruct(ir, side \\ nil, path \\ [])

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

  def deconstruct(%IR.Symbol{name: name}, :left, path) do
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

  def deconstruct(ir, :left, path) do
    [[{:left_value, ir} | path]]
  end

  def deconstruct(_ir, :right, path) do
    [[:right_value | path]]
  end
end
