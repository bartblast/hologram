alias Hologram.Compiler.{Context, JSEncoder, MapKeyEncoder, Opts}
alias Hologram.Compiler.IR.{Binding, MapAccess, MatchAccess, ParamAccess, TupleAccess, VariableAccess}

defimpl JSEncoder, for: Binding do
  def encode(%{access_path: access_path, name: name}, %Context{} = context, %Opts{} = opts) do
    statement = if name in context.block_bindings, do: "", else: "let "
    initial_acc = "#{statement}#{name} = "

    access_path
    |> Enum.reduce(initial_acc, fn part, acc ->
      acc <> encode_part(part, context, opts)
    end)
    |> Kernel.<>(";")
  end

  defp encode_part(%MapAccess{key: key}, context, opts) do
    encoded_key = MapKeyEncoder.encode(key, context, opts)
    ".data['#{encoded_key}']"
  end

  defp encode_part(%MatchAccess{}, _context, _opts) do
    "window.$hologramMatchAccess"
  end

  defp encode_part(%ParamAccess{index: index}, _context, _opts) do
    "arguments[#{index}]"
  end

  defp encode_part(%TupleAccess{index: index}, _context, _opts) do
    ".data[#{index}]"
  end

  defp encode_part(%VariableAccess{name: name}, _context, _opts) do
    to_string(name)
  end
end
