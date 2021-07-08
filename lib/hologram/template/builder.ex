defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Helpers, Processor}
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

  def build(module) do
    aliases =
      Helpers.module_name_segments(module)
      |> Processor.get_module_definition()
      |> Map.get(:aliases)

    module.template()
    |> Parser.parse!()
    |> Transformer.transform(aliases)
  end
end
