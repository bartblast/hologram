defmodule Hologram.Compiler.OverhaulTransformer do
  alias Hologram.Compiler.IR

  # DEFINITIONS

  def transform({:defmacro, _, _}) do
    %IR.IgnoredExpression{type: :macro_definition}
  end
end
