defmodule Hologram.Template.Interpolator do
  alias Hologram.Compiler.{Context, Parser}
  alias Hologram.Compiler.Typespecs, as: T
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}

  @doc """
  Splits text nodes into text nodes and expression nodes
  and replaces element nodes' attribute values containing expressions with expression nodes.
  Works on the nodes tree recursively.

  ## Examples
      iex> nodes = [
      iex>   %TextNode{},
      iex>   %ElementNode{
      iex>     children: [%TextNode{}],
      iex>     attrs: %{"key" => "{1}"}
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
  @spec interpolate(list(T.document_node())) :: list(T.document_node())

  def interpolate(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ interpolate_node(&1)))
  end

  defp interpolate_node(%Component{children: children, props: props} = node) do
    children = interpolate(children)
    props = interpolate_props(props)

    [%{node | children: children, props: props}]
  end

  defp interpolate_node(%ElementNode{children: children, attrs: attrs} = node) do
    children = interpolate(children)
    attrs = interpolate_attrs(attrs)

    [%{node | children: children, attrs: attrs}]
  end

  defp interpolate_node(%TextNode{content: content} = node) do
    regex = ~r/([^\{]*)(\{[^\}]*\})([^\{]*)/

    nodes =
      Regex.scan(regex, content)
      |> Enum.reduce([], fn [_, left, expr, right], acc ->
        acc
        |> maybe_include_text_node(left)
        |> maybe_include_expression(expr)
        |> maybe_include_text_node(right)
      end)

    if nodes != [], do: nodes, else: [node]
  end

  defp interpolate_node(node), do: [node]

  defp interpolate_attrs(attrs) do
    Enum.map(attrs, fn {key, spec} ->
      {key, %{spec | value: interpolate_value(spec.value)}}
    end)
    |> Enum.into(%{})
  end

  defp interpolate_props(props) do
    Enum.map(props, fn {key, value} ->
      {key, interpolate_value(value)}
    end)
    |> Enum.into(%{})
  end

  _ = """
  Returns the corresponding expression node if an expression is found in the value string.
  If there is no expression in the value string, the string itself is returned.

  ## Examples
      iex> interpolate_value("{1}")
      %Expression{ir: %IntegerType{value: 1}}
  """

  @spec interpolate_value(String.t()) :: %Expression{} | String.t()

  defp interpolate_value(str) do
    regex = ~r/^(\{.+\})$/

    case Regex.run(regex, str) do
      [_, code] ->
        %Expression{ir: get_ir(code)}

      _ ->
        str
    end
  end

  defp get_ir(code) do
    Parser.parse!(code)
    # TODO: pass actual %Context{} struct received from compiler
    |> Hologram.Compiler.Transformer.transform(%Context{})
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
