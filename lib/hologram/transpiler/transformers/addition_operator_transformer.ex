defmodule Hologram.Transpiler.AdditionOperatorTransformer do
  alias Hologram.Transpiler.AST.AdditionOperator
  alias Hologram.Transpiler.Transformer

  def transform(left, right, current_module, imports, aliases) do
    %AdditionOperator{
      left: Transformer.transform(left, current_module, imports, aliases),
      right: Transformer.transform(right, current_module, imports, aliases)
    }
  end
end
