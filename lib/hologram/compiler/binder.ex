defmodule Hologram.Compiler.Binder do
  alias Hologram.Compiler.IR.{MapAccess, MapType, Variable}

  def bind(value, path \\ [])

  def bind(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ bind(value, path ++ [%MapAccess{key: key}])
    end)
  end

  def bind(%Variable{} = var, path) do
    [path ++ [var]]
  end

  def bind(_, _) do
    []
  end
end
