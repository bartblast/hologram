defmodule Hologram.Template.Builder do
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer
  alias Hologram.Template.VDOMTree

  def build(markup) do
    markup
    |> remove_doctype()
    |> remove_comments()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> Parser.parse()
    |> VDOMTree.build()
  end

  defp remove_comments(markup) do
    Regex.replace(~r/<!\-\-.*\-\->/sU, markup, "")
  end

  defp remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
  end
end
