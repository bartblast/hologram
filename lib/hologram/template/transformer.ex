# TODO: test
defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.{Parser, Transformer}
  alias Hologram.Template.Interpolator
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, Expression, TextNode}

  def transform(dom, aliases \\ %{})

  def transform(dom, aliases) when is_list(dom) do
    Enum.map(dom, fn node -> transform(node, aliases) end)
  end

  def transform({type, attrs, children}, aliases) do
    children =
      Enum.map(children, fn child -> transform(child, aliases) end)
      |> Interpolator.interpolate()

    case determine_node_type(type, aliases) do
      :component ->
        module = String.split(type, ".") |> Enum.map(&String.to_atom/1)
        %Component{module: module, children: children}

      :element ->
        attrs = build_element_attrs(attrs)
        %ElementNode{tag: type, attrs: attrs, children: children}
    end
  end

  def transform(dom, _aliases) when is_binary(dom) do
    %TextNode{content: dom}
  end

  defp build_element_attrs(attrs) do
    Enum.map(attrs, fn {key, value} ->
      regex = ~r/^{{(.+)}}$/

      value =
        case Regex.run(regex, value) do
          [_, code] ->
            ir =
              Parser.parse!(code)
              |> Hologram.Compiler.Transformer.transform()

            %Expression{ir: ir}

          _ ->
            value
        end

      {key, value}
    end)
    |> Enum.into(%{})
  end

  defp determine_node_type(type, aliases) do
    first_char = String.at(type, 0)

    if first_char == String.downcase(first_char) do
      :element
    else
      :component
    end
  end
end
