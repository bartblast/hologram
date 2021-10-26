alias Hologram.Compiler.Helpers
alias Hologram.Template.VDOM.Component
alias Hologram.Template.Encoder

defimpl Encoder, for: Component do
  import Hologram.Commons.Encoder

  def encode(%{module: module, children: children, props: props}) do
    class_name = Helpers.class_name(module)
    encoded_children = Encoder.encode(children)
    encoded_props = encode_props(props)

    "{ type: 'component', module: '#{class_name}', children: #{encoded_children}, props: #{encoded_props} }"
  end

  defp encode_prop(name, value) do
    "'#{name}': #{Encoder.encode(value)}"
  end

  defp encode_props(props) do
    props
    |> Enum.map(fn {name, value} -> encode_prop(name, value) end)
    |> Enum.join(", ")
    |> wrap_with_object()
  end
end
