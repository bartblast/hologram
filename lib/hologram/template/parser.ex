defmodule Hologram.Template.Parser do
  use Hologram.Commons.Parser
  alias Hologram.Template.{TokenCombiner, Tokenizer}

  @impl Hologram.Commons.Parser
  def parse(markup) do
    context = %{
      attrs: [],
      attr_key: nil,
      double_quote_opened?: 0,
      tag: nil,
      tokens: [],
      num_open_braces: 0
    }

    Tokenizer.tokenize(markup)
    |> TokenCombiner.combine(:text, context, [])
    |> Enum.map(&to_html/1)
    |> Enum.join("")
    |> Floki.parse_document!()
    |> remove_empty_text_nodes()
  end

  defp remove_empty_text_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&remove_empty_text_nodes/1)
  end

  defp remove_empty_text_nodes({tag, attrs, children}) do
    {tag, attrs, remove_empty_text_nodes(children)}
  end

  defp remove_empty_text_nodes(text), do: text

  defp to_html({:start_tag, {tag, attrs}}) do
    attrs =
      Enum.map(attrs, fn {key, value} ->
        if value do
          key <> "=\"" <> value <> "\""
        else
          key <> "=\"\""
        end
      end)

    "<#{tag} #{attrs}>"
  end

  defp to_html({:end_tag, tag}) do
    "</#{tag}>"
  end

  defp to_html({:text, str}) do
    str
  end
end
