defmodule Hologram.Compiler.PatternMatching do
  alias Hologram.Compiler.IR

  def deconstruct(ir, side \\ nil, path \\ [])

  def deconstruct(%IR.ListType{data: data}, side, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      list_index_path = [{:list_index, index} | path]
      acc ++ deconstruct(value, side, list_index_path)
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
