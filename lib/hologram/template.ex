defmodule Hologram.Template do
  alias Hologram.Compiler.AST
  alias Hologram.Template.DOM
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer

  @doc """
  Builds DOM tree AST from the given template markup.

  ## Examples

      iex> dom_tree_ast("<div>content</div>")
      [{:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}]
  """
  @spec dom_tree_ast(String.t()) :: AST.t()
  def dom_tree_ast(markup) do
    markup
    |> remove_doctype()
    |> remove_comments()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> Parser.parse()
    |> DOM.tree_ast()
  end

  defmacro sigil_H({:<<>>, _meta, [markup]}, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defmacro sigil_H(markup, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defp build_h_sigil_ast(markup) do
    quote do
      fn var!(data) ->
        _fix_unused_data_var = var!(data)
        unquote(dom_tree_ast(markup))
      end
    end
  end

  defp remove_comments(markup) do
    Regex.replace(~r/<!\-\-.*\-\->/sU, markup, "")
  end

  defp remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
  end
end
