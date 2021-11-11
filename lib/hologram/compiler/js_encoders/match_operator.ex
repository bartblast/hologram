alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.{DotOperator, MapAccess, MatchOperator}

defimpl JSEncoder, for: MatchOperator do
  def encode(%{bindings: bindings, right: right}, %Context{} = context, %Opts{} = opts) do
    Enum.reduce(bindings, "", fn binding, acc ->
      binding_js = encode_binding(binding, right, context, opts)
      Formatter.maybe_append_new_line(acc, binding_js)
    end)
    |> Formatter.append_line_break()
  end

  def convert_ir(path, value) when is_list(path) do
    Enum.reduce(path, value, &convert_ir/2)
  end

  def convert_ir(%MapAccess{key: key}, ir) do
    %DotOperator{left: ir, right: key}
  end

  defp encode_binding({var, path}, right, context, opts) do
    ir = convert_ir(path, right)
    "const #{var} = " <> JSEncoder.encode(ir, context, opts)
  end
end
