defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Context, Reflection}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Typespecs, as: T
  alias Hologram.Utils

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
    # module def store can't be used here, because template builder is run
    # by compiler before module def store aggregates module defs.
    module_def = Reflection.module_definition(module)

    context = %Context{
      aliases: module_def.aliases,
      imports: module_def.imports
    }

    module.template()
    |> Parser.parse!()
    |> Transformer.transform(context)
  end

  # DEFER: test
  def build_all(modules) do
    modules
    |> Utils.map_async(&{&1, build(&1)})
    |> Utils.await_tasks()
    |> Enum.into(%{})
  end
end
