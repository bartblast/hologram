defmodule Hologram.Compiler.Detransformer do
  alias Hologram.Compiler.IR

  @doc """
  Detransforms Hologram IR to Elixir AST.

  ## Examples
      iex> ir = %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
      iex> Detransformer.detransform(ir)
      {:+, [line: 0], [1, 2]}
  """
  def detransform(ir)

  # --- OPERATORS ---

  def detransform(%IR.AdditionOperator{left: left, right: right}) do
    detransform_binary_operator(:+, left, right)
  end

  def detransform(%IR.DivisionOperator{left: left, right: right}) do
    detransform_binary_operator(:/, left, right)
  end

  def detransform(%IR.DotOperator{left: left, right: right}) do
    left = detransform(left)
    right = detransform(right)

    {{:., [line: 0], [left, right]}, [no_parens: true, line: 0], []}
  end

  def detransform(%IR.EqualToOperator{left: left, right: right}) do
    detransform_binary_operator(:==, left, right)
  end

  def detransform(%IR.LessThanOperator{left: left, right: right}) do
    detransform_binary_operator(:<, left, right)
  end

  def detransform(%IR.ListConcatenationOperator{left: left, right: right}) do
    detransform_binary_operator(:++, left, right)
  end

  def detransform(%IR.ListSubtractionOperator{left: left, right: right}) do
    detransform_binary_operator(:--, left, right)
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
    {:%{}, [line: 0], data}
  end

  def detransform(%IR.ModuleType{segments: segments}) do
    {:__aliases__, [line: 0], segments}
  end

  def detransform(%IR.NilType{}) do
    nil
  end

  def detransform(%IR.StructType{module: module, data: data}) do
    module = detransform(module)
    data = detransform_key_value_pairs(data)

    {:%, [line: 0], [module, {:%{}, [line: 0], data}]}
  end

  # --- CONTROL FLOW ---

  def detransform(%IR.FunctionCall{module: module, function: function, args: args}) do
    module = detransform(module)
    args = detransform_list(args)

    {{:., [line: 0], [module, function]}, [line: 0], args}
  end

  def detransform(%IR.Variable{name: name}) do
    {name, [line: 0], nil}
  end

  # --- HELPERS ---

  defp detransform_binary_operator(marker, left, right) do
    left = detransform(left)
    right = detransform(right)

    {marker, [line: 0], [left, right]}
  end

  defp detransform_key_value_pairs(data) do
    Enum.map(data, fn {key, value} ->
      {detransform(key), detransform(value)}
    end)
  end

  defp detransform_list(list) do
    Enum.map(list, &detransform/1)
  end
end
