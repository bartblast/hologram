defmodule Hologram.Compiler.BinaryTypeTransformer do
  alias Hologram.Compiler.IR.BinaryType
  alias Hologram.Compiler.Transformer

  def transform({:<<>>, _, parts}) do
    parts = Enum.map(parts, &Transformer.transform/1)
    %BinaryType{parts: parts}
  end
end
