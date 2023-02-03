defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  def detransform(list) when is_list(list) do
    Enum.map(list, &detransform/1)
  end

  def detransform(%IR.AdditionOperator{left: left, right: right}) do
    left = detransform(left)
    right = detransform(right)

    {:+, [line: 0], [left, right]}
  end

  def detransform(%IR.FunctionCall{module: module, function: function, args: args}) do
    module = detransform(module)
    args = detransform(args)

    {{:., [line: 0], [module, function]}, [line: 0], args}
  end

  def detransform(%IR.ModuleType{segments: segments}) do
    {:__aliases__, [line: 0], segments}
  end

  def detransform(%IR.IntegerType{value: value}) do
    value
  end

  def detransform(%IR.Variable{name: name}) do
    {name, [line: 0], nil}
  end
end
