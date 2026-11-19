defmodule Hologram.Template.DOM do
  @moduledoc false

  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.AST
  alias Hologram.Template.EventModifiers
  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser
  alias Hologram.TemplateSyntaxError

  # Tags a key would name nothing new. "document" and "window" render no node at all, and "slot"
  # renders whatever is put in its place. The three page-level elements are each the only one of
  # their kind, so a key cannot tell them from a sibling - and the patch reaches them by name
  # rather than through an ordinary children diff, which a key would make it refuse: the root is
  # rebuilt into a document that allows only one element, and head and body would be thrown away
  # and rebuilt on every navigation, taking the stylesheets and the scroll position with them.
  @unkeyable_tags ["body", "document", "head", "html", "slot", "window"]

  @type attribute :: {String.t(), t} | {:spread, {any}}

  # 'dom_node' name used instead of 'node" because type node/0 is a built-in type and it cannot be redefined.
  @type dom_node ::
          {:component, module, list(attribute), t}
          | {:dynamic_tag, {any}, list(attribute), t}
          | {:element, String.t(), list(attribute), t}
          | {:expression, {any}}
          | {:page, module, list(attribute), []}
          | {:public_comment, t}
          | {:text, String.t()}

  @type t :: dom_node | list(dom_node())

  @doc """
  Builds DOM AST from the given parsed tags.

  ## Examples

      iex> tags = [{:start_tag, {"div", []}}, {:text, "abc"}, {:end_tag, "div"}]
      iex> build_ast(tags)
      [{:{}, [line: 1], [:element, "div", [], [{:text, "abc"}]]}]
  """
  @spec build_ast(list(Parser.parsed_tag())) :: AST.t()
  def build_ast(tags) do
    # The code below is built from fragments that pair up only when the tags do, so tags that don't
    # are refused here, with a message about the template rather than about the generated code.
    validate_nesting(tags)

    # The keys name places in this template, so they are built from the hash of the template as
    # written, before any of them has been added to it.
    hash = template_hash(tags)

    {code, _last_tag_type} =
      tags
      |> add_slot_keys(hash)
      |> Enum.reduce({"", nil}, fn tag, {code_acc, last_tag_type} ->
        current_tag_type = if is_tuple(tag), do: elem(tag, 0), else: tag

        # :skip items are fully elided, as if they did not appear
        case render_code(tag) do
          :skip ->
            {code_acc, last_tag_type}

          current_tag_code ->
            {append_code(code_acc, current_tag_code, last_tag_type), current_tag_type}
        end
      end)

    "[#{code}]"
    |> AST.for_code()
    |> substitute_module_attributes()
  end

  @doc """
  Names the template a key belongs to.

  Distinguishes a key from another template's, since slot content is spliced into the surrounding
  template's children and bare indexes would collide there. Derived from the tags rather than the
  module name so that it stays stable across renames and needs no caller context. Two byte-identical
  templates share a hash, which leaves their keys to be told apart by their position among siblings,
  the same way a loop's repeats are.

  `:erlang.phash2/2` is documented to return the same value for a given term regardless of machine
  architecture and ERTS version, which is what lets tests assert key text verbatim.
  """
  @spec template_hash(list(Parser.parsed_tag())) :: String.t()
  def template_hash(tags) do
    tags
    |> normalize_newlines()
    |> :erlang.phash2(4_294_967_296)
    |> Integer.to_string(36)
    |> String.downcase()
  end

  # The key trails the attributes the template author wrote, so that reading a tag reads what was
  # written first, and appending is the point rather than an oversight.
  # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
  defp add_slot_key(attributes, hash, index), do: attributes ++ [slot_key_attribute(hash, index)]

  # Gives every element the key of the place it holds in this template, counted in source order.
  #
  # A key is what lets the diff pair an element with itself across renders whatever happens around
  # it: a block that starts rendering an extra node shifts its siblings' positions but not their
  # keys, so the sibling is still matched with itself rather than with the block's content.
  #
  # Counted per template rather than globally, and prefixed with the template's hash, because slot
  # content is spliced into a children list belonging to another template, where bare counters
  # would collide.
  #
  # Only elements are keyed. A component has no node of its own - it renders the nodes of its own
  # template, which carry their own keys - and the tags that produce no node at all have nothing to
  # key.
  defp add_slot_keys(tags, hash) do
    {keyed_tags, _index} = Enum.map_reduce(tags, 0, &inject_slot_key(&1, &2, hash))

    keyed_tags
  end

  defp append_code(code_acc, code, last_tag_type)
       when last_tag_type in [
              :block_end,
              :doctype,
              :end_tag,
              :expression,
              :public_comment_end,
              :self_closing_tag,
              :text
            ] do
    code_acc <> ", " <> code
  end

  defp append_code(code_acc, code, _last_tag_type) do
    code_acc <> code
  end

  # Closes the innermost open entry with the given closer, or refuses the closer when it can't.
  defp close_entry([], closer) do
    raise TemplateSyntaxError,
      message: "#{describe_closer(closer)} has no matching #{describe_opener(closer)}"
  end

  defp close_entry([top | rest], closer) do
    if matches_closer?(top, closer) do
      reopen_entry(rest, closer)
    else
      refuse_closer(top, Enum.find(rest, &matches_closer?(&1, closer)), closer)
    end
  end

  # Splits a "$"-prefixed event attribute name on "." into the bare name and its
  # raw modifier segments. Names without "$" (or without ".") carry no modifiers.
  defp decompose_event_attribute_name("$" <> _rest = name) do
    case String.split(name, ".") do
      [base_name] -> {base_name, []}
      [base_name | modifiers] -> {base_name, modifiers}
    end
  end

  defp decompose_event_attribute_name(name), do: {name, []}

  defp describe_closer({:block_end, block_name}), do: "{/#{block_name}}"

  defp describe_closer({:block_start, "else"}), do: "{%else}"

  defp describe_closer({:end_tag, tag_name}), do: "</#{tag_name_source(tag_name)}>"

  defp describe_closer(:public_comment_end), do: "-->"

  # An {%if} block that has reached its {%else} is still the {%if} block to the person who wrote it.
  defp describe_entry({:block, "else"}), do: "the {%if} block"

  defp describe_entry({:block, block_name}), do: "the {%#{block_name}} block"

  defp describe_entry(:public_comment), do: "the public comment"

  defp describe_entry({:tag, tag_name}), do: "the <#{tag_name_source(tag_name)}> tag"

  defp describe_entry_closer({:block, "else"}), do: "{/if}"

  defp describe_entry_closer({:block, block_name}), do: "{/#{block_name}}"

  defp describe_entry_closer(:public_comment), do: "-->"

  defp describe_entry_closer({:tag, tag_name}), do: "</#{tag_name_source(tag_name)}>"

  defp describe_opener({:block_end, block_name}), do: "{%#{block_name}}"

  defp describe_opener({:end_tag, tag_name}), do: "<#{tag_name_source(tag_name)}>"

  defp extract_expression_content(expr_str) do
    expr_str
    |> String.slice(1, String.length(expr_str) - 2)
    |> String.trim()
  end

  defp inject_slot_key({tag_type, {tag_name, attributes}}, index, hash)
       when tag_type in [:start_tag, :self_closing_tag] do
    if keyable_tag?(tag_name) do
      {{tag_type, {tag_name, add_slot_key(attributes, hash, index)}}, index + 1}
    else
      {{tag_type, {tag_name, attributes}}, index}
    end
  end

  defp inject_slot_key(tag, index, _hash), do: {tag, index}

  # A dynamic tag is keyed too: it renders an element whenever its expression names one, and a key
  # reaching a component instead is dropped with the rest of the props it does not declare.
  defp keyable_tag?({:expression, _templ_expr}), do: true

  defp keyable_tag?(tag_name) do
    Helpers.tag_type(tag_name) == :element and tag_name not in @unkeyable_tags
  end

  defp matches_closer?({:block, "else"}, {:block_end, "if"}), do: true

  defp matches_closer?({:block, block_name}, {:block_end, block_name}), do: true

  defp matches_closer?({:block, block_name}, {:block_start, "else"})
       when block_name in ["if", "else"],
       do: true

  defp matches_closer?(:public_comment, :public_comment_end), do: true

  defp matches_closer?({:tag, open_tag_name}, {:end_tag, tag_name}) do
    same_tag_name?(open_tag_name, tag_name)
  end

  defp matches_closer?(_entry, _closer), do: false

  # Wraps implicit keyword list.
  # {a: 1, b: 2} is not valid Elixir code, although {123, a: 1, b: 2} is allowed.
  defp normalize_implicit_keyword_list(templ_expr) do
    regex = ~r/^\{\s*(([a-zA-Z_][a-zA-Z0-9_]*[?!]?|"[^"]+"):\s.+)\}$/s

    case Regex.run(regex, templ_expr) do
      [_full, content, _beginning] ->
        "{[#{content}]}"

      nil ->
        templ_expr
    end
  end

  # Templates checked out on Windows carry CRLF line endings, which would otherwise give the same
  # template a different hash per platform, so keys could not be asserted verbatim.
  defp normalize_newlines(term) when is_binary(term) do
    StringUtils.normalize_newlines(term)
  end

  defp normalize_newlines(term) when is_list(term) do
    Enum.map(term, &normalize_newlines/1)
  end

  defp normalize_newlines(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.map(&normalize_newlines/1)
    |> List.to_tuple()
  end

  defp normalize_newlines(term), do: term

  # Refuses a closer that doesn't close the innermost open entry, given the deeper entry it closes,
  # if any.
  #
  # Tags inside a public comment are text, so an end tag reaches an open comment only when the
  # parser didn't end the comment, and is told the comment isn't closed, whether or not it closes
  # something outside the comment.
  defp refuse_closer(:public_comment, _match, {:end_tag, _tag_name} = closer) do
    raise TemplateSyntaxError, message: unclosed_before_message(:public_comment, closer)
  end

  defp refuse_closer(top, nil, closer) do
    raise TemplateSyntaxError,
      message:
        "#{describe_closer(closer)} has no matching #{describe_opener(closer)} inside #{describe_entry(top)}"
  end

  # The parser reads block markers inside a public comment, so a commented-out {%else} or {/if}
  # reaches here as one.
  defp refuse_closer(:public_comment, match, closer) do
    raise TemplateSyntaxError,
      message:
        "#{describe_closer(closer)} belongs to #{describe_entry(match)} outside the public comment"
  end

  defp refuse_closer(top, _match, closer) do
    raise TemplateSyntaxError, message: unclosed_before_message(top, closer)
  end

  defp render_attribute_code({:spread, templ_expr}, _tag_type) do
    "{:spread, #{normalize_implicit_keyword_list(templ_expr)}}"
  end

  defp render_attribute_code({name, value_parts}, :element) do
    value_code = Enum.map_join(value_parts, ", ", &render_code/1)

    case decompose_event_attribute_name(name) do
      {base_name, []} ->
        "{\"#{base_name}\", [#{value_code}]}"

      {base_name, modifiers} ->
        "{\"#{base_name}\", [#{value_code}], #{render_event_modifiers(base_name, modifiers)}}"
    end
  end

  defp render_attribute_code({name, value_parts}, _tag_type) do
    "{\"#{name}\", [" <> Enum.map_join(value_parts, ", ", &render_code/1) <> "]}"
  end

  defp render_code({:block_start, "else"}) do
    "] else ["
  end

  defp render_code({:block_start, {"for", expr_str}}) do
    "(for #{extract_expression_content(expr_str)} do ["
  end

  defp render_code({:block_end, "for"}) do
    "] end)"
  end

  defp render_code({:block_start, {"if", expr_str}}) do
    "(if #{extract_expression_content(expr_str)} do ["
  end

  defp render_code({:block_end, "if"}) do
    "] end)"
  end

  # `raw` blocks are useful only in the handling of template sources.
  # `Parser` emits them so that such source can be reconstructed.
  # They can be skipped in the building of the AST here.
  defp render_code({:block_start, "raw"}) do
    :skip
  end

  defp render_code({:block_end, "raw"}) do
    :skip
  end

  defp render_code({:doctype, content}) do
    "{:doctype, \"#{content}\"}"
  end

  defp render_code({:end_tag, _tag_name}) do
    "]}"
  end

  defp render_code({:expression, templ_expr}) do
    "{:expression, #{normalize_implicit_keyword_list(templ_expr)}}"
  end

  defp render_code(:public_comment_end) do
    "]}"
  end

  defp render_code(:public_comment_start) do
    "{:public_comment, ["
  end

  defp render_code({:self_closing_tag, {tag_name, attributes}}) do
    render_code({:start_tag, {tag_name, attributes}}) <> render_code({:end_tag, tag_name})
  end

  # The tag name expression is already brace-wrapped, so emitting its source produces the one-tuple
  # holding the runtime value. Attributes use element-style event decomposition, since the element
  # branch is the only one that can consume events - the component branch filters them out anyway.
  defp render_code({:start_tag, {{:expression, templ_expr}, attributes}}) do
    attributes_code = Enum.map_join(attributes, ", ", &render_attribute_code(&1, :element))

    "{:dynamic_tag, #{templ_expr}, [#{attributes_code}], ["
  end

  defp render_code({:start_tag, {tag_name, attributes}}) do
    tag_type = Helpers.tag_type(tag_name)

    if tag_name in ["window", "document"] do
      validate_reserved_tag_attributes(tag_name, attributes)
    end

    # HTML source carries no tag-name case, so the name is written the way the parser would spell
    # it. The compiled template feeds the server and the client alike, so both then agree - and the
    # client, which builds elements rather than parsing them, gets a name it can build.
    tag_name_code =
      if tag_type == :element do
        "\"#{Helpers.normalize_tag_name(tag_name)}\""
      else
        "alias!(#{tag_name})"
      end

    attributes_code =
      Enum.map_join(attributes, ", ", &render_attribute_code(&1, tag_type))

    "{:#{tag_type}, #{tag_name_code}, [#{attributes_code}], ["
  end

  defp render_code({:text, str}) do
    escaped_str =
      str
      |> HtmlEntities.decode()
      |> String.replace(~s("), ~s(\\"))

    ~s({:text, "#{escaped_str}"})
  end

  # Every event's raw segments are parsed and validated into tagged modifiers at compile time.
  defp render_event_modifiers(base_name, modifiers) do
    inspect(EventModifiers.parse(base_name, modifiers))
  end

  # An {%else} closes the branch of its {%if} block before it and opens the one after it, which can
  # only be closed by {/if}.
  defp reopen_entry(rest, {:block_start, "else"}), do: [{:block, "else"} | rest]

  defp reopen_entry(rest, _closer), do: rest

  # Two sources of a dynamic tag name name the same tag when they are the same code, however they
  # are spaced. A source that isn't valid code can only be the same as itself.
  defp same_expression?(source_1, source_2) do
    with {:ok, ast_1} <- Code.string_to_quoted(source_1),
         {:ok, ast_2} <- Code.string_to_quoted(source_2) do
      Macro.to_string(ast_1) == Macro.to_string(ast_2)
    else
      _error -> source_1 == source_2
    end
  end

  defp same_tag_name?({:expression, open_source}, {:expression, source}) do
    same_expression?(open_source, source)
  end

  defp same_tag_name?(open_tag_name, tag_name)
       when is_binary(open_tag_name) and is_binary(tag_name) do
    # HTML end tags are matched regardless of case, so an element's end tag can be spelled in any
    # case. A component's name is a module alias, which is spelled one way only.
    if Helpers.tag_type(open_tag_name) == :element do
      String.downcase(open_tag_name) == String.downcase(tag_name)
    else
      open_tag_name == tag_name
    end
  end

  defp same_tag_name?(_open_tag_name, _tag_name), do: false

  defp slot_key_attribute(hash, index) do
    {"$key", [{:text, "#{hash}:#{index}"}]}
  end

  defp substitute_module_attributes({:@, meta_1, [{name, _meta_2, _args}]}) do
    {{:., meta_1, [{:vars, meta_1, nil}, name]}, [{:no_parens, true} | meta_1], []}
  end

  defp substitute_module_attributes(ast) when is_list(ast) do
    Enum.map(ast, &substitute_module_attributes/1)
  end

  defp substitute_module_attributes(ast) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.map(&substitute_module_attributes/1)
    |> List.to_tuple()
  end

  defp substitute_module_attributes(ast), do: ast

  defp tag_name_source({:expression, source}), do: source

  defp tag_name_source(tag_name), do: tag_name

  defp track_nesting({:block_end, _block_name} = closer, stack) do
    close_entry(stack, closer)
  end

  defp track_nesting({:block_start, "else"} = closer, stack) do
    # Found past the tags and comments open inside it, so that an {%else} in an element in an {%if}
    # block is told it's inside the element, and one in a {%for} block is told it belongs in an if.
    innermost_block = Enum.find(stack, &match?({:block, _block_name}, &1))

    cond do
      innermost_block not in [{:block, "if"}, {:block, "else"}] ->
        raise TemplateSyntaxError, message: "{%else} can only be used in an {%if} block"

      match?([{:block, "else"} | _rest], stack) ->
        raise TemplateSyntaxError, message: "the {%if} block has more than one {%else}"

      true ->
        close_entry(stack, closer)
    end
  end

  defp track_nesting({:block_start, "raw"}, stack), do: [{:block, "raw"} | stack]

  defp track_nesting({:block_start, {block_name, _expression}}, stack) do
    [{:block, block_name} | stack]
  end

  defp track_nesting({:end_tag, tag_name} = closer, stack) do
    # The parser reads the start tag of a void element as self-closing, testing the name as written,
    # so a void element's end tag closes something only when its start tag is spelled in another
    # case, like <iNPUT></input>. Any other one is refused as an end tag the element can't have.
    if void_end_tag?(tag_name) and not Enum.any?(stack, &matches_closer?(&1, closer)) do
      raise TemplateSyntaxError,
        message: "</#{tag_name}> isn't allowed, since <#{tag_name}> has no end tag"
    end

    close_entry(stack, closer)
  end

  defp track_nesting(:public_comment_end = closer, stack) do
    close_entry(stack, closer)
  end

  defp track_nesting(:public_comment_start, stack), do: [:public_comment | stack]

  defp track_nesting({:start_tag, {tag_name, _attributes}}, stack) do
    [{:tag, tag_name} | stack]
  end

  defp track_nesting(_tag, stack), do: stack

  defp unclosed_before_message(top, closer) do
    "#{describe_entry(top)} isn't closed before #{describe_closer(closer)}, add #{describe_entry_closer(top)}"
  end

  defp validate_closed([]), do: :ok

  defp validate_closed([top | _rest]) do
    raise TemplateSyntaxError,
      message: "#{describe_entry(top)} isn't closed, add #{describe_entry_closer(top)}"
  end

  # Checks that every start tag, block and public comment is closed by its own closer, and every
  # closer closes an open one, innermost first.
  defp validate_nesting(tags) do
    tags
    |> Enum.reduce([], &track_nesting/2)
    |> validate_closed()
  end

  # The <window> and <document> tags bind events to the window or document and nothing else, so each
  # attribute must be an event binding (a "$"-prefixed name). Any other attribute fails the build.
  defp validate_reserved_tag_attributes(tag_name, attributes) do
    Enum.each(attributes, fn
      # Spread entries can't carry event bindings, since "$"-prefixed keys are rejected at runtime.
      {:spread, _templ_expr} ->
        raise TemplateSyntaxError,
          message: ~s'the <#{tag_name}> tag accepts only event bindings, but got a spread'

      {name, _value_parts} ->
        unless String.starts_with?(name, "$") do
          raise TemplateSyntaxError,
            message:
              ~s'the <#{tag_name}> tag accepts only event bindings, but got the "#{name}" attribute'
        end
    end)
  end

  defp void_end_tag?({:expression, _source}), do: false

  # An element's name has no case, so its end tag is void however it's spelled. A component's name
  # is a module alias, and a component always has an end tag.
  defp void_end_tag?(tag_name) do
    if Helpers.tag_type(tag_name) == :element do
      tag_name
      |> String.downcase()
      |> Helpers.void_element?()
    else
      false
    end
  end
end
