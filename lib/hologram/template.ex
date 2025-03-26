defmodule Hologram.Template do
  @moduledoc false

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
    |> String.trim()
    |> Tokenizer.tokenize()
    |> Parser.parse_tokens()
    |> DOM.build_ast()
  end

  defmacro sigil_HOLO({:<<>>, _meta, [markup]}, _modifiers) do
    build_holo_sigil_ast(markup)
  end

  defmacro sigil_HOLO(markup, _modifiers) do
    build_holo_sigil_ast(markup)
  end

  defp build_holo_sigil_ast(markup) do
    quote do
      fn var!(vars) ->
        # Fixes unused var warning
        # credo:disable-for-next-line Credo.Check.Consistency.UnusedVariableNames
        _ = var!(vars)
        unquote(dom_ast(markup))
      end
    end
  end
end
