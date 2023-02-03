defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  def detransform(%IR.IntegerType{value: value}) do
    value
  end
end
