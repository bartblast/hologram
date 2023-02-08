defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  def detransform(list) when is_list(list) do
    Enum.map(list, &detransform/1)
  end

  def detransform(%{kind: :basic_data_type, value: value}) do
    value
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

  def detransform(%IR.ListType{data: data}) do
    detransform(data)
  end

  def detransform(%IR.ModuleType{segments: segments}) do
    {:__aliases__, [line: 0], segments}
  end

  def detransform(%IR.StructType{module: module_ir, data: data_ir}) do
    acc = [{:__struct__, module_ir.module}]

    data =
      data_ir
      |> Enum.reduce(acc, fn {key, value}, acc ->
        [{key.value, detransform(value)} | acc]
      end)
      |> Enum.reverse()

    {:%{}, [], data}
  end

  def detransform(%IR.Variable{name: name}) do
    {name, [line: 0], nil}
  end
end
