defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.{Helpers, Parser, Resolver, Transformer}
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Template.Interpolator
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Typespecs, as: T

  @doc """
  Builds virtual DOM from parsed HTML.
  Interpolates expression nodes in text nodes and attribute values.
  """
  @spec transform(Saxy.SimpleForm.t, list(%Alias{})) :: list(T.virtual_dom_node)

  def transform(dom, aliases \\ []) do
    Enum.map(dom, fn node -> transform_node(node, aliases) end)
    |> Interpolator.interpolate()
  end

  defp transform_node(dom, _) when is_binary(dom) do
    %TextNode{content: dom}
  end

  defp transform_node({type, attrs, children}, aliases) do
    children = Enum.map(children, &transform_node(&1, aliases))

    case determine_node_type(type, aliases) do
      :component ->
        build_component(type, children, aliases)

      :element ->
        build_element_node(type, children, attrs)
    end
  end

  defp build_component(module_name, children, aliases) do
    module =
      Helpers.module_name_segments(module_name)
      |> Resolver.resolve(aliases)

    %Component{module: module, children: children}
  end

  defp build_element_node(tag, children, attrs) do
    attrs = Enum.into(attrs, %{})
    %ElementNode{tag: tag, children: children, attrs: attrs}
  end

  defp determine_node_type(type, _) do
    first_char = String.at(type, 0)
    downcased_first_char = String.downcase(first_char)

    if first_char == downcased_first_char do
      :element
    else
      :component
    end
  end
end
