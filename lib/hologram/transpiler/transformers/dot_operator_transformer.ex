defmodule Hologram.Transpiler.DotOperatorTransformer do
  alias Hologram.Transpiler.AST.DotOperator
  alias Hologram.Transpiler.Transformer

  def transform(left, right, current_module, imports, aliases) do
    %DotOperator{
      left: Transformer.transform(left, current_module, imports, aliases),
      right: Transformer.transform(right, current_module, imports, aliases)
    }
  end
end
