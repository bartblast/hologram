defmodule Hologram.TemplateEngine.Interpolator do
  alias Hologram.TemplateEngine.AST.{Expression, TextNode}
  alias Hologram.Transpiler.Parser

  def interpolate(nodes) do
    Enum.reduce(nodes, [], fn node, acc ->
      case node do
        %TextNode{text: text} ->
          acc ++ split_text_node(nodes, node, text)

        _ ->
          acc ++ [Map.put(node, :children, interpolate(node.children))]
      end
    end)
  end

  defp handle_match(match, char_count, nodes) do
    text = Enum.at(match, 1)

    {char_count, nodes} =
      if text != "" do
        {char_count + String.length(text), nodes ++ [%TextNode{text: text}]}
      else
        {char_count, nodes}
      end

    code = Enum.at(match, 3)

    ast =
      Parser.parse!(code)
      |> Hologram.Transpiler.Transformer.transform()

    {char_count, nodes} = {char_count + 4 + String.length(code), nodes ++ [%Expression{ast: ast}]}
  end

  defp handle_matches(text, matches) do
    {char_count, nodes} =
      Enum.reduce(matches, {0, []}, fn match, {char_count, nodes} ->
        handle_match(match, char_count, nodes)
      end)

    length = String.length(text)
    remainder = String.slice(text, char_count, length - char_count)

    if remainder != "" do
      nodes ++ [%TextNode{text: remainder}]
    else
      nodes
    end
  end

  defp split_text_node(nodes, node, text) do
    regex = ~r/(.*)(\{\{(.+)\}\})/U

    case Regex.scan(regex, text) do
      [] ->
        [node]

      matches ->
        handle_matches(text, matches)
    end
  end
end
