defmodule Hologram.Transpiler.Binder do
  alias Hologram.Transpiler.AST.{MapAccess, MapType, Variable}

  def bind(_, path \\ [])

  def bind(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ bind(value, path ++ [%MapAccess{key: key}])
    end)
  end

  def bind(%Variable{name: name} = var, path) do
    [[var] ++ path]
  end

  def bind(_, path) do
    []
  end
end
