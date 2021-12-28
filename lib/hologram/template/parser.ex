defmodule Hologram.Template.Parser do
  alias Hologram.Template.{TokenCombiner, TokenHTMLEncoder, Tokenizer}

  def parse!(markup) do
    context = %{
      attrs: [],
      attr_key: nil,
      double_quote_opened?: 0,
      num_open_braces: 0,
      prev_tokens: [],
      tag_name: nil,
      token_buffer: []
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

  # DEFER: remove once custom HTML parser is implemented, see: https://github.com/segmetric/hologram/issues/18
  defp remove_empty_text_nodes(arg)

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
