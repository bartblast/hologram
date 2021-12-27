defmodule Hologram.Template.Parser do
  alias Hologram.Template.{TokenCombiner, TokenHTMLEncoder, Tokenizer}

  def parse!(markup) do
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
    |> unescape_double_quotes()
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

  defp unescape_double_quotes(nodes) when is_list(nodes) do
    Enum.map(nodes, &unescape_double_quotes/1)
  end

  defp unescape_double_quotes({tag, attrs, children}) do
    escaped_double_quote = TokenHTMLEncoder.escaped_double_quote()

    attrs =
      Enum.map(attrs, fn {key, value} ->
        value = String.replace(value, escaped_double_quote, "\"")
        {key, value}
      end)

    {tag, attrs, unescape_double_quotes(children)}
  end

  defp unescape_double_quotes(text), do: text
end
