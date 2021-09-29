alias Hologram.Template.Document.ElementNode
alias Hologram.Template.Encoder

defimpl Encoder, for: ElementNode do
  def encode(%{tag: tag, attrs: attrs, children: children}) do
    attrs_js = encode_attrs(attrs)
    children_js = encode_nodes(children)

    "{ type: 'element', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end

  defp encode_array(js) do
    if js != "", do: "[ #{js} ]", else: "[]"
  end

  defp encode_attr(name, %{value: value, modifiers: modifiers}) do
    value = encode_nodes(value)
    modifiers = encode_modifiers(modifiers)
    "'#{name}': { value: #{value}, modifiers: #{modifiers} }"
  end

  defp encode_attrs(attrs) do
    if Enum.any?(attrs) do
      js =
        attrs
        |> Enum.map(fn {name, spec} -> encode_attr(name, spec) end)
        |> Enum.join(", ")

      "{ #{js} }"
    else
      "{}"
    end
  end

  defp encode_modifiers(modifiers) do
    Enum.map(modifiers, &"'#{&1}'")
    |> Enum.join(", ")
    |> encode_array()
  end

  defp encode_nodes(nodes) do
    Enum.map(nodes, &Encoder.encode(&1))
    |> Enum.join(", ")
    |> encode_array()
  end
end
