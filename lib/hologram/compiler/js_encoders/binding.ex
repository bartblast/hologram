alias Hologram.Compiler.{Config, Context, JSEncoder, MapKeyEncoder, Opts}

alias Hologram.Compiler.IR.{
  Binding,
  CaseConditionAccess,
  ListIndexAccess,
  MapAccess,
  MatchAccess,
  ParamAccess,
  TupleAccess
}

defimpl JSEncoder, for: Binding do
  def encode(%{access_path: access_path, name: name}, %Context{} = context, %Opts{} = opts) do
    encoded_parts = Enum.reduce(access_path, "", &encode_part(&1, &2, context, opts))
    statement = if name in context.block_bindings, do: "", else: "let "
    "#{statement}#{name} = #{encoded_parts};"
  end

  defp encode_part(%CaseConditionAccess{}, acc, _context, _opts) do
    acc <> Config.case_condition_js()
  end

  defp encode_part(%ListIndexAccess{index: index}, acc, _context, _opts) do
    acc <> ".data[#{index}]"
  end

  defp encode_part(%MapAccess{key: key}, acc, context, opts) do
    encoded_key = MapKeyEncoder.encode(key, context, opts)
    acc <> ".data['#{encoded_key}']"
  end

  defp encode_part(%MatchAccess{}, acc, _context, _opts) do
    acc <> Config.match_access_js()
  end

  defp encode_part(%ParamAccess{index: index}, acc, _context, _opts) do
    acc <> "arguments[#{index}]"
  end

  defp encode_part(%TupleAccess{index: index}, acc, _context, _opts) do
    acc <> ".data[#{index}]"
  end
end
