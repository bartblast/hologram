defmodule Hologram.Template do
  @moduledoc """
  Templates: the `~HOLO` sigil for writing a component's or a page's template, and `trust_html/1`,
  which marks HTML for a template to output as markup. Both are imported into every component and
  page. Other modules call `Hologram.Template.trust_html/1`.
  """

  alias Hologram.Compiler.AST
  alias Hologram.Template.DOM
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer
  alias Hologram.Template.TrustedHTML

  # Builds DOM AST from the given template markup, e.g. dom_ast("<div>content</div>").
  @doc false
  @spec dom_ast(String.t()) :: AST.t()
  def dom_ast(markup) do
    markup
    |> String.trim()
    |> Tokenizer.tokenize()
    |> Parser.parse_tokens()
    |> DOM.build_ast()
  end

  @doc ~S'''
  Builds a template from the given markup.

  ## Examples

      ~HOLO"""
      <p>Hello, {@name}!</p>
      """
  '''
  defmacro sigil_HOLO({:<<>>, _meta, [markup]}, _modifiers) do
    build_holo_sigil_ast(markup)
  end

  defmacro sigil_HOLO(markup, _modifiers) do
    build_holo_sigil_ast(markup)
  end

  @doc """
  Marks the given HTML, a string or iodata, as trusted, so a template outputs it as markup instead
  of escaping it.

  Interpolated as an element's content, as in `{@body}`, the HTML goes on the page inline among
  its siblings, with no wrapper element. Malformed markup, like an unclosed or a stray tag, is
  fixed first. Interpolating it where markup can't go raises, for example in an attribute, in a
  `<script>`, `<style>`, `<textarea>` or `<title>` element, or inside an HTML comment. If the
  browser moves the HTML out of place when it loads the page, because it isn't valid there, like a
  `<div>` inside a `<p>`, the client raises.

  `trust_html/1` doesn't sanitize the HTML you give it. If users wrote any of it, sanitize it before
  you mark it. Script elements are removed, so they never run, but that isn't sanitizing. Event
  handler attributes and `javascript:` URLs stay, and only Hologram's default Content Security
  Policy keeps them from running.

  ## Examples

      iex> trust_html("<p>Hello</p>")
      %Hologram.Template.TrustedHTML{html: "<p>Hello</p>"}

      iex> trust_html(["<p>", "Hello", "</p>"])
      %Hologram.Template.TrustedHTML{html: "<p>Hello</p>"}
  """
  @spec trust_html(iodata) :: TrustedHTML.t()
  def trust_html(html) when is_binary(html), do: %TrustedHTML{html: html}

  def trust_html(html) when is_list(html), do: %TrustedHTML{html: IO.iodata_to_binary(html)}

  def trust_html(html) do
    raise ArgumentError, "trust_html/1 takes a string or iodata, got: #{inspect(html)}"
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
