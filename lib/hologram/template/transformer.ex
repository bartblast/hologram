defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.{Parser, Transformer}
  alias Hologram.Template.Interpolator
  alias Hologram.Template.VirtualDOM.{ComponentNode, Expression, TagNode, TextNode}

  def transform(dom, aliases \\ %{})

  def transform(dom, aliases) when is_list(dom) do
    Enum.map(dom, fn node -> transform(node, aliases) end)
  end

  def transform({type, attrs, children}, aliases) do
    children =
      Enum.map(children, fn child -> transform(child, aliases) end)
      |> Interpolator.interpolate()

    attrs =
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

    case resolve_node_type(type, aliases) do
      :tag ->
        %TagNode{tag: type, attrs: attrs, children: children}
        # TODO: imlement
        # :module ->
        #   %ComponentNode{module: module, children: children}
    end
  end

  def transform(dom, _aliases) when is_binary(dom) do
    %TextNode{text: dom}
  end

  # TODO: implement
  defp resolve_node_type(type, aliases) do
    :tag
  end
end
