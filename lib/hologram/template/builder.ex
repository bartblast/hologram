defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Context, Reflection}
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

  def build(module) do
    # DEFER: consider - use module def store, see: https://github.com/segmetric/hologram/issues/7
    module_def = Reflection.module_definition(module)

    context = %Context{
      aliases: module_def.aliases,
      imports: module_def.imports
    }

    module.template()
    |> Parser.parse!()
    |> Transformer.transform(context)
  end
end
