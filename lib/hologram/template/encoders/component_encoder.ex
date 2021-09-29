alias Hologram.Compiler.Helpers
alias Hologram.Template.Document.Component
alias Hologram.Template.Encoder

defimpl Encoder, for: Component do
  def encode(%{module: module, children: children}) do
    class_name = Helpers.class_name(module)
    children = Encoder.encode(children)

    "{ type: 'component', module: '#{class_name}', children: #{children} }"
  end
end
