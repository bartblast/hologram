alias Hologram.Template.VDOM.ElementNode
alias Hologram.Template.Encoder

defimpl Encoder, for: ElementNode do
  use Hologram.Commons.Encoder

  def encode(%{tag: tag, attrs: attrs, children: children}) do
    encoded_attrs = encode_attrs(attrs)
    encoded_children = Encoder.encode(children)

    "{ type: 'element', tag: '#{tag}', attrs: #{encoded_attrs}, children: #{encoded_children} }"
  end

  defp encode_attr(name, %{value: value, modifiers: modifiers}) do
    value = Encoder.encode(value)
    modifiers = encode_modifiers(modifiers)
    "'#{name}': { value: #{value}, modifiers: #{modifiers} }"
  end

  defp encode_attrs(attrs) do
    attrs
    |> Enum.map(fn {name, spec} -> encode_attr(name, spec) end)
    |> Enum.join(", ")
    |> wrap_with_object()
  end

  defp encode_modifiers(modifiers) do
    Enum.map(modifiers, &"'#{&1}'")
    |> Enum.join(", ")
    |> wrap_with_array()
  end
end
