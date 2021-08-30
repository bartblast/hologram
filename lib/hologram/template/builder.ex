defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Helpers, Reflection}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Typespecs, as: T

  @doc """
  Returns module's document tree template.

  ## Examples
      iex> build(Demo.Homepage)
      [
        %ElementNode{tag: "h1", children: [%TextNode{content: "Homepage Title"}]},
        %TextNode{content: "Footer content"}
      ]
  """
  @spec build(module()) :: list(T.document_node)

  def build(module, layout \\ nil) do
    aliases =
      Reflection.module_definition(module)
      |> Map.get(:aliases)

    template =
      if layout do
        layout_name = Helpers.module_name(layout)
        "<#{layout_name}>#{module.template()}</#{layout_name}>"
      else
        module.template()
      end

    template
    |> Parser.parse!()
    |> Transformer.transform(aliases)
  end
end
