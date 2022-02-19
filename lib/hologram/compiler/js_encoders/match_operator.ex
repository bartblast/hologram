alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.{DotOperator, FunctionCall, IntegerType, MapAccess, MatchOperator, TupleAccess}

defimpl JSEncoder, for: MatchOperator do
  def encode(%{bindings: bindings, right: right}, %Context{} = context, %Opts{} = opts) do
    Enum.map(bindings, fn binding ->
      encode_binding(binding, right, context, opts)
    end)
    |> Enum.join(";\n")
  end

  def convert_ir(path, value) when is_list(path) do
    Enum.reduce(path, value, &convert_ir/2)
  end

  def convert_ir(%MapAccess{key: key}, ir) do
    %DotOperator{left: ir, right: key}
  end

  def convert_ir(%TupleAccess{index: index}, ir) do
    %FunctionCall{
      module: Kernel,
      function: :elem,
      args: [ir, %IntegerType{value: index}]
    }
  end

  defp encode_binding({var, path}, right, context, opts) do
    ir = convert_ir(path, right)
    "const #{var} = " <> JSEncoder.encode(ir, context, opts)
  end
end
