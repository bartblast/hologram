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

  def detransform(%IR.EqualToOperator{left: left, right: right}) do
    left = detransform(left)
    right = detransform(right)

    {:==, [line: 0], [left, right]}
  end

  def detransform(%IR.FunctionCall{module: module, function: function, args: args}) do
    module = detransform(module)
    args = detransform(args)

    {{:., [line: 0], [module, function]}, [line: 0], args}
  end

  def detransform(%IR.ListType{data: data}) do
    detransform(data)
  end

  def detransform(%IR.MapType{data: data_ir}) do
    data = detransform_key_value_pairs(data_ir)
    {:%{}, [], data}
  end

  def detransform(%IR.ModuleType{segments: segments}) do
    {:__aliases__, [line: 0], segments}
  end

  def detransform(%IR.NilType{}) do
    nil
  end

  def detransform(%IR.StructType{module: module_ir, data: data_ir}) do
    struct_module = {:__struct__, module_ir.module}
    data = [struct_module | detransform_key_value_pairs(data_ir)]

    {:%{}, [], data}
  end

  def detransform(%IR.Variable{name: name}) do
    {name, [line: 0], nil}
  end

  defp detransform_key_value_pairs(data) do
    Enum.map(data, fn {key, value} ->
      {detransform(key), detransform(value)}
    end)
  end
end
