defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.AST
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer
  alias Hologram.Template.VDOMTree

  @doc """
  Convertes the given template markup into the AST of Elixir code that creates the corresponding VDOM tree.

  ## Examples

      iex> build("<div>content</div>")
      [{:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}]
  """
  @spec build(String.t()) :: AST.t()
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
