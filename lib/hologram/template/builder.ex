defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Context, Helpers, Reflection}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Typespecs, as: T

  @doc """
  Returns module's VDOM template.

  ## Examples
      iex> build(MyApp.Homepage)
      [
        %ElementNode{tag: "h1", children: [%TextNode{content: "Homepage Title"}]},
        %TextNode{content: "Footer content"}
      ]
  """
  @spec build(module()) :: list(T.vdom_node())

  def build(module, layout \\ nil) do
    module_def = Reflection.module_definition(module)

    context = %Context{
      aliases: module_def.aliases,
      imports: module_def.imports
    }

    build_template(module, layout)
    |> Parser.parse!()
    |> Transformer.transform(context)
  end

  defp build_template(module, nil), do: module.template()

  defp build_template(module, layout) do
    layout_name = Helpers.module_name(layout)
    "<#{layout_name}>#{module.template()}</#{layout_name}>"
  end
end
