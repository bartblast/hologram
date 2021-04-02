defmodule Hologram.TemplateEngine.Transformer do
  alias Hologram.TemplateEngine.AST.ComponentNode
  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode

  def transform(ast, aliases \\ %{})

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

  def transform(ast, _aliases) when is_binary(ast) do
    %TextNode{text: ast}
  end
end
