defmodule Hologram.Template.Interpolator do
  alias Hologram.Compiler.{Normalizer, Parser, Transformer}
  alias Hologram.Template.VirtualDOM.{Expression, TextNode}

  def interpolate(nodes) do
    Enum.reduce(nodes, [], fn node, acc ->
      case node do
        %TextNode{content: content} ->
          acc ++ split_text_node(nodes, node, content)

        _ ->
          acc ++ [Map.put(node, :children, interpolate(node.children))]
      end
    end)
  end

  defp handle_match(match, char_count, nodes) do
    content = Enum.at(match, 1)

    {char_count, nodes} =
      if content != "" do
        {char_count + String.length(content), nodes ++ [%TextNode{content: content}]}
      else
        {char_count, nodes}
      end

    code = Enum.at(match, 3)

    ir =
      Parser.parse!(code)
      |> Normalizer.normalize()
      |> Transformer.transform()

    {char_count, nodes} = {char_count + 4 + String.length(code), nodes ++ [%Expression{ir: ir}]}
  end

  defp handle_matches(content, matches) do
    {char_count, nodes} =
      Enum.reduce(matches, {0, []}, fn match, {char_count, nodes} ->
        handle_match(match, char_count, nodes)
      end)

    length = String.length(content)
    remainder = String.slice(content, char_count, length - char_count)

    if remainder != "" do
      nodes ++ [%TextNode{content: remainder}]
    else
      nodes
    end
  end

  defp split_text_node(nodes, node, content) do
    regex = ~r/(.*)(\{\{(.+)\}\})/U

    case Regex.scan(regex, content) do
      [] ->
        [node]

      matches ->
        handle_matches(content, matches)
    end
  end
end
