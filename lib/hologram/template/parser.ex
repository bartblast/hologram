defmodule Hologram.Template.Parser do
  alias Hologram.Template.{DOMTreeBuilder, TokenCombiner, Tokenizer}

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
    |> remove_comments()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> TokenCombiner.combine(:text_tag, context, [])
    |> DOMTreeBuilder.build()
  end

  defp remove_comments(markup) do
    Regex.replace(~r/<!\-\-.*\-\->/sU, markup, "")
  end

  defp remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
  end
end
