defmodule Hologram.TemplateEngine.Transformer do
  alias Hologram.TemplateEngine.AST.ComponentNode
  alias Hologram.TemplateEngine.AST.TagNode

  def transform(ast, aliases \\ %{})

  def transform(ast, aliases) when is_list(ast) do
    Enum.map(ast, fn element -> transform(element, aliases) end)
  end

  def transform({type, attrs, children}, aliases) do
    children = Enum.map(children, fn child -> transform(child, aliases) end)

    case resolve_node_type(type, aliases) do
      :tag ->
        %TagNode{tag: type, children: children}
      # TODO: imlement
      # :module ->
      #   %ComponentNode{module: module, children: children}
    end
  end

  # TODO: implement
  defp resolve_node_type(type, aliases) do
    :tag
  end
end
