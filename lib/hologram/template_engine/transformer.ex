defmodule Hologram.TemplateEngine.Transformer do
  alias Hologram.TemplateEngine.AST.TagNode

  def transform(ast) when is_list(ast) do
    Enum.map(ast, fn element -> transform(element) end)
  end

  def transform({type, attrs, children}) do
    children = Enum.map(children, fn child -> transform(child) end)
    %TagNode{tag: type, children: children}
  end
end
