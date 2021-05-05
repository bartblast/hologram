defmodule Hologram.Compiler.Binder do
  alias Hologram.Compiler.AST.{MapAccess, MapType, Variable}

  def bind(_, path \\ [])

  def bind(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ bind(value, path ++ [%MapAccess{key: key}])
    end)
  end

  def bind(%Variable{name: name} = var, path) do
    [path ++ [var]]
  end

  def bind(_, path) do
    []
  end
end
