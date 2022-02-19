defmodule Hologram.Compiler.PatternBinder do
  alias Hologram.Compiler.IR.{MapAccess, MapType, TupleAccess, TupleType, Variable}

  def bind(value, path \\ [])

  def bind(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ bind(value, path ++ [%MapAccess{key: key}])
    end)
  end

  def bind(%TupleType{data: data}, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      acc ++ bind(value, path ++ [%TupleAccess{index: index}])
    end)
  end

  def bind(%Variable{} = var, path) do
    [path ++ [var]]
  end

  def bind(_, _) do
    []
  end
end
