alias Hologram.Compiler.{Context, JSEncoder, MapKeyEncoder, Opts}
alias Hologram.Compiler.IR.{Binding, MapAccess, ParamAccess}

defimpl JSEncoder, for: Binding do
  def encode(%{access_path: access_path, name: name}, %Context{} = context, %Opts{} = opts) do
    access_path
    |> Enum.reduce("let #{name} = ", fn part, acc ->
      acc <> encode_part(part, context, opts)
    end)
    |> Kernel.<>(";")
  end

  defp encode_part(%MapAccess{key: key}, context, opts) do
    encoded_key = MapKeyEncoder.encode(key, context, opts)
    ".data['#{encoded_key}']"
  end

  defp encode_part(%ParamAccess{index: index}, _context, _opts) do
    "arguments[#{index}]"
  end
end
