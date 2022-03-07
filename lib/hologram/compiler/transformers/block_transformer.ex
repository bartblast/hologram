defmodule Hologram.Compiler.BlockTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.Block

  def transform({:__block__, _, ast}, %Context{} = context) do
    ir = Enum.map(ast, &Transformer.transform(&1, context))
    %Block{expressions: ir}
  end
end
