defmodule Hologram.Template.Interpolator do
  alias Hologram.Compiler.Parser
  alias Hologram.Template.VirtualDOM.{ElementNode, Expression, TextNode}
  alias Hologram.Compiler.Typespecs, as: T

  @doc """
  Splits text nodes into text nodes and expression nodes
  and replaces element nodes' attribute values containing expressions with expression nodes.
  Works on the nodes tree recursively.

  ## Examples
      iex> nodes = [
      iex>   %TextNode{},
      iex>   %ElementNode{
      iex>     children: [%TextNode{}],
      iex>     attrs: %{"key" => "{{ 1 }}"}
      iex>   }
      iex> ]
      iex> interpolate(nodes)
      [
        %Expression{}
        %TextNode{},
        %ElementNode{
          children: [%TextNode{}, %Expression{}],
          attrs: %{"key" => %Expression{}}
        }
      ]
  """
  @spec interpolate(list(T.virtual_dom_node())) :: list(T.virtual_dom_node())

  def interpolate(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ interpolate_node(&1)))
  end

  defp interpolate_node(%ElementNode{children: children, attrs: attrs} = node) do
    children = interpolate(children)

    attrs =
      Enum.map(attrs, fn {key, value} -> {key, interpolate_attr(value)} end)
      |> Enum.into(%{})

    [%{node | children: children, attrs: attrs}]
  end

  defp interpolate_node(%TextNode{content: content} = node) do
    regex = ~r/([^\{]*)(\{\{([^\}]*)\}\})([^\{]*)/

    nodes =
      Regex.scan(regex, content)
      |> Enum.reduce([], fn [_, left, _, expr, right], acc ->
        acc
        |> maybe_include_text_node(left)
        |> maybe_include_expression(expr)
        |> maybe_include_text_node(right)
      end)

    if nodes != [], do: nodes, else: [node]
  end

  defp interpolate_node(node), do: [node]

  _ = """
  Returns the corresponding expression node if an expression is found in the attribute value string.
  If there is no expression in the attribute value string, the string itself is returned.

  ## Examples
      iex> interpolate_attr("{{ 1 }}")
      %Expression{ir: %IntegerType{value: 1}}
  """

  @spec interpolate_attr(String.t()) :: %Expression{} | String.t()

  defp interpolate_attr(str) do
    regex = ~r/^\{\{(.+)\}\}$/

    case Regex.run(regex, str) do
      [_, code] ->
        %Expression{ir: get_ir(code)}

      _ ->
        str
    end
  end

  defp get_ir(code) do
    Parser.parse!(code)
    |> Hologram.Compiler.Transformer.transform()
  end

  defp maybe_include_expression(acc, code) do
    if String.length(code) > 0 do
      acc ++ [%Expression{ir: get_ir(code)}]
    else
      acc
    end
  end

  defp maybe_include_text_node(acc, str) do
    if String.length(str) > 0 do
      acc ++ [%TextNode{content: str}]
    else
      acc
    end
  end
end
