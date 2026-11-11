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
    build_holo_sigil_ast(markup, __CALLER__)
  end

  defmacro sigil_HOLO(markup, _modifiers) do
    build_holo_sigil_ast(markup, __CALLER__)
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

  defp build_holo_sigil_ast(markup, env) do
    dom_ast = dom_ast(markup)

    validate_no_element_lookup(dom_ast, env)

    quote do
      fn var!(vars) ->
        # Fixes unused var warning
        # credo:disable-for-next-line Credo.Check.Consistency.UnusedVariableNames
        _ = var!(vars)
        unquote(dom_ast)
      end
    end
  end

  # A template renders on the server too, where JS.element/1 returns a placeholder, and in the
  # browser the element it would look up may not exist until the render that names it is done. Any
  # arity counts, so a pipe into it and a capture of it are caught too, called through an alias or
  # an import alike.
  defp validate_no_element_lookup(dom_ast, env) do
    Macro.prewalk(dom_ast, fn node ->
      if element_lookup?(node, env) do
        raise Hologram.CompileError, message: element_lookup_message(env.module)
      end

      node
    end)
  end

  defp element_lookup?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, _parts} = alias_ast, :element]}, _meta,
          _args},
         env
       ) do
    Macro.expand(alias_ast, env) == Hologram.JS
  end

  # A capture of an imported function holds its name the way a variable is held, so it's matched
  # with the capture around it, which leaves a variable named element divided by 1 alone.
  defp element_lookup?(
         {:&, _meta, [{:/, _slash_meta, [{:element, _name_meta, context}, 1]}]},
         env
       )
       when is_atom(context) do
    {:function, Hologram.JS} in Macro.Env.lookup_import(env, {:element, 1})
  end

  defp element_lookup?({:element, _meta, args}, env) when is_list(args) do
    {:function, Hologram.JS} in Macro.Env.lookup_import(env, {:element, 1})
  end

  defp element_lookup?(_node, _env), do: false

  defp element_lookup_message(module) do
    template = if module, do: "the template of #{inspect(module)}", else: "a template"

    "JS.element/1 can't be called in #{template} - a template also renders on the server, " <>
      "and in the browser the element it names may not exist yet, so pass the ref itself, " <>
      "like scroll_ref={:feed}, and look the element up in an action"
  end
end
