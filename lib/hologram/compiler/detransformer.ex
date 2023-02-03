defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  def detransform(%IR.IntegerType{value: value}) do
    value
  end

  def detransform(%IR.Variable{name: name}) do
    {name, [], nil}
  end
end
