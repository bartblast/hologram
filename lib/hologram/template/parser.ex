defmodule Hologram.Template.Parser do
  alias Hologram.Template.DOMTreeBuilder
  alias Hologram.Template.TagAssembler
  alias Hologram.Template.Tokenizer

  def parse!(markup) do
    markup
    |> remove_doctype()
    |> remove_comments()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> TagAssembler.assemble()
    |> DOMTreeBuilder.build()
  end

  def remove_comments(markup) do
    Regex.replace(~r/<!\-\-.*\-\->/sU, markup, "")
  end

  def remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
  end
end
