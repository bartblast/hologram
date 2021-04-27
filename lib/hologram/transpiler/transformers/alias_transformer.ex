defmodule Hologram.Transpiler.AliasTransformer do
  alias Hologram.Transpiler.AST.Alias

  def transform({:alias, _, [{_, _, module}]}) do
    %Alias{module: module, as: [List.last(module)]}
  end

  def transform({:alias, _, [{_, _, module}, [as: {_, _, as}]]}) do
    %Alias{module: module, as: as}
  end
end
