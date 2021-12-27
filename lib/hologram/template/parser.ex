defmodule Hologram.Template.Parser do
  use Hologram.Commons.Parser
  alias Hologram.Template.{TokenCombiner, TokenHTMLEncoder, Tokenizer}

  @impl Hologram.Commons.Parser
  def parse(markup) do
    context = %{
      attrs: [],
      attr_key: nil,
      double_quote_opened?: 0,
      prev_tokens: [],
      tag: nil,
      tokens: [],
      num_open_braces: 0
    }

    markup
    |> remove_doctype()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> TokenCombiner.combine(:text_tag, context, [])
    |> Enum.map(&TokenHTMLEncoder.encode/1)
    |> Enum.join("")
    |> Floki.parse_document!()
    |> remove_empty_text_nodes()
  end

  defp remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
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
end
