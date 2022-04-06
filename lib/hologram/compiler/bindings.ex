defmodule Hologram.Compiler.Bindings do
  alias Hologram.Compiler.IR.{MapAccess, MapType, TupleAccess, TupleType, Variable}

  def find(value, path \\ [])

  def find(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ find(value, path ++ [%MapAccess{key: key}])
    end)
  end

  def find(%TupleType{data: data}, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      acc ++ find(value, path ++ [%TupleAccess{index: index}])
    end)
  end

  def find(%Variable{} = var, path) do
    [path ++ [var]]
  end

  def find(_, _) do
    []
  end
end
