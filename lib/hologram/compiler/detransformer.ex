defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  # --- OPERATORS ---

  def detransform(%IR.AdditionOperator{left: left, right: right}) do
    left = detransform(left)
    right = detransform(right)

    {:+, [line: 0], [left, right]}
  end

  # --- DATA TYPES ---

  def detransform(%IR.AtomType{value: value}), do: value

  def detransform(%IR.BooleanType{value: value}), do: value

  def detransform(%IR.FloatType{value: value}), do: value

  def detransform(%IR.IntegerType{value: value}), do: value

  def detransform(%IR.ListType{data: data}) do
    detransform_list(data)
  end

  def detransform(%IR.MapType{data: data}) do
    data = detransform_key_value_pairs(data)
    {:%{}, [], data}
  end

  def detransform(%IR.ModuleType{segments: segments}) do
    {:__aliases__, [line: 0], segments}
  end

  def detransform(%IR.NilType{}) do
    nil
  end

  def detransform(%IR.StructType{module: module_ir, data: data_ir}) do
    module_ast = {:__struct__, module_ir.module}
    data_ast = [module_ast | detransform_key_value_pairs(data_ir)]

    {:%{}, [], data_ast}
  end

  # --- HELPERS ---

  defp detransform_key_value_pairs(data) do
    Enum.map(data, fn {key, value} ->
      {detransform(key), detransform(value)}
    end)
  end

  defp detransform_list(list) do
    Enum.map(list, &detransform/1)
  end

  # --- OVERHAUL ---

  # def detransform(%IR.EqualToOperator{left: left, right: right}) do
  #   left = detransform(left)
  #   right = detransform(right)

  #   {:==, [line: 0], [left, right]}
  # end

  # def detransform(%IR.FunctionCall{module: module, function: function, args: args}) do
  #   module = detransform(module)
  #   args = detransform(args)

  #   {{:., [line: 0], [module, function]}, [line: 0], args}
  # end

  # def detransform(%IR.Variable{name: name}) do
  #   {name, [line: 0], nil}
  # end
end
