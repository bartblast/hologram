defmodule Hologram.Compiler.BlockTransformer do
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.Transformer

  def transform({:__block__, _, ast}) do
    ir = Enum.map(ast, &Transformer.transform/1)
    %Block{expressions: ir}
  end
end
