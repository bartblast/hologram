defmodule Hologram.Template do
  alias Hologram.Compiler.AST
  alias Hologram.Template.DOM
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer

  @doc """
  Builds DOM AST from the given template markup.

  ## Examples

      iex> dom_ast("<div>content</div>")
      [{:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}]
  """
  @spec dom_ast(String.t()) :: AST.t()
  def dom_ast(markup) do
    markup
    |> remove_doctype()
    |> remove_comments()
    |> String.trim()
    |> Tokenizer.tokenize()
    |> Parser.parse_tokens()
    |> DOM.build_ast()
  end

  defmacro sigil_H({:<<>>, _meta, [markup]}, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defmacro sigil_H(markup, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defp build_h_sigil_ast(markup) do
    quote do
      fn var!(vars) ->
        _fix_unused_var_warning = var!(vars)
        unquote(dom_ast(markup))
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
