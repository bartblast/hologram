defmodule Hologram.Template.DOM do
  @moduledoc false

  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.AST
  alias Hologram.Identifier
  alias Hologram.Template.DataTransfer
  alias Hologram.Template.EventModifiers
  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser
  alias Hologram.TemplateSyntaxError

  # The refs that name the window and the document, which a template can't give an element.
  @built_in_refs [:window, :document]

  @ref_expectation "$ref takes an identifier, like :search or {:message, 42}"

  # Tags a key would name nothing new. "document" and "window" render no node at all, and "slot"
  # renders whatever is put in its place. The three page-level elements are each the only one of
  # their kind, so a key cannot tell them from a sibling - and the patch reaches them by name
  # rather than through an ordinary children diff, which a key would make it refuse: the root is
  # rebuilt into a document that allows only one element, and head and body would be thrown away
  # and rebuilt on every navigation, taking the stylesheets and the scroll position with them.
  @unkeyable_tags ["body", "document", "head", "html", "slot", "window"]

  # The variable a loop's generator binds the whole item to, so that the renderers can key the item
  # by its :id however the generator's pattern takes it apart. Not underscore-prefixed, since the
  # transpiler turns such a name into a wildcard that binds nothing.
  @loop_item_var :holo_loop_item

  @type attribute :: {String.t(), t} | {:spread, {any}}

  # 'dom_node' name used instead of 'node" because type node/0 is a built-in type and it cannot be redefined.
  @type dom_node ::
          {:component, module, list(attribute), t}
          | {:dynamic_tag, {any}, list(attribute), t}
          | {:element, String.t(), list(attribute), t}
          | {:expression, {any}}
          | {:loop_item, {any} | nil, t}
          | {:page, module, list(attribute), []}
          | {:public_comment, t}
          | {:text, String.t()}

  @type t :: dom_node | list(dom_node())

  @doc """
  Builds DOM AST from the given parsed tags.

  ## Examples

      iex> tags = [{:start_tag, {"div, []}}, {:text, "abc"}, {:end_tag, "div"}]
      iex> build_ast(tags)
      [{:{}, [line: 1], [:element, "div", [], [{:text, "abc"}]]}]
  """
  @spec build_ast(list(Parser.parsed_tag())) :: AST.t()
  def build_ast(tags) do
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
  # written first, and appending is the point rather than an oversight. A $key the author wrote
  # follows the key of the place inside the same attribute, where the renderers read it.
  defp add_slot_key(attributes, hash, index, author_key_parts) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    attributes ++ [slot_key_attribute(hash, index, author_key_parts)]
  end

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
  # Only elements are keyed for their place. A component has no node of its own - it renders the
  # nodes of its own template, which carry their own keys - and the tags that produce no node at all
  # have nothing to key.
  #
  # A $key the template author writes keys a loop item's tag by the item's identity instead of its
  # position, so it goes only on a tag that renders straight into the loop's children list: one
  # whose nearest enclosing tag or block, past any if blocks, is the for block. On an element it
  # joins the key of the element's place, and on a component it stays as a prop the renderers read
  # to key every node the component renders.
  defp add_slot_keys(tags, hash) do
    {keyed_tags, _acc} = Enum.map_reduce(tags, {0, []}, &inject_slot_key(&1, &2, hash))

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

  # Whether the attribute is a $data_transfer, with modifiers or without.
  defp data_transfer_attribute?({name, _value_parts}) when is_binary(name) do
    match?({"$data_transfer", _modifiers}, decompose_event_attribute_name(name))
  end

  defp data_transfer_attribute?(_spread), do: false

  defp data_transfer_entry({key, value_ast}) do
    if Macro.quoted_literal?(value_ast) do
      {key, literal_value(value_ast)}
    else
      {key, %DataTransfer.Unknown{}}
    end
  end

  # The value a $data_transfer expression gives, read off its source as far as the source tells it:
  # {:ok, value}, with %DataTransfer.Unknown{} in place of each value of a keyword list or map that
  # only the render knows, like an assign. :unknown when the source doesn't tell even the shape. The
  # braces holding one value give that value, and holding none or several give the tuple, as the
  # renderers read them.
  defp data_transfer_literal(expr_str) do
    case expr_str
         |> normalize_implicit_keyword_list()
         |> Code.string_to_quoted(emit_warnings: false) do
      {:ok, {:{}, _meta, [value_ast]}} -> data_transfer_term(value_ast)
      {:ok, tuple_ast} -> data_transfer_term(tuple_ast)
      {:error, _reason} -> :unknown
    end
  end

  defp data_transfer_pairs?(ast) when is_list(ast) do
    Enum.all?(ast, &match?({key, _value_ast} when is_atom(key), &1))
  end

  defp data_transfer_pairs?(_ast), do: false

  # A map is built entry by entry, before the literal case, so a repeated key keeps the last value
  # the way the map does when it renders, without evaluating the map.
  defp data_transfer_term(ast) do
    cond do
      match?({:%{}, _meta, _pairs}, ast) and data_transfer_pairs?(elem(ast, 2)) ->
        entries =
          ast
          |> elem(2)
          |> Map.new(&data_transfer_entry/1)

        {:ok, entries}

      Macro.quoted_literal?(ast) ->
        {:ok, literal_value(ast)}

      data_transfer_pairs?(ast) ->
        {:ok, Enum.map(ast, &data_transfer_entry/1)}

      true ->
        :unknown
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

  # Whether the attribute is a $drop binding, with modifiers or without.
  defp drop_attribute?({name, _value_parts}) when is_binary(name) do
    match?({"$drop", _modifiers}, decompose_event_attribute_name(name))
  end

  defp drop_attribute?(_spread), do: false

  defp extract_expression_content(expr_str) do
    expr_str
    |> String.slice(1, String.length(expr_str) - 2)
    |> String.trim()
  end

  # The generator's pattern is matched against the item as before, and the item is bound whole
  # beside it. A guard stays outside the match, where the generator's syntax puts it.
  defp bind_loop_item({:<-, meta, [{:when, when_meta, [pattern, guard]}, enum]}) do
    {:<-, meta, [{:when, when_meta, [bind_loop_item_pattern(pattern), guard]}, enum]}
  end

  defp bind_loop_item({:<-, meta, [pattern, enum]}) do
    {:<-, meta, [bind_loop_item_pattern(pattern), enum]}
  end

  defp bind_loop_item(qualifier), do: qualifier

  defp bind_loop_item_pattern(pattern) do
    {:=, [], [pattern, {@loop_item_var, [], nil}]}
  end

  # The accumulator holds the index of the next keyed element and the stack of tags and blocks open
  # around the current tag, innermost first.
  defp inject_slot_key({tag_type, {tag_name, attributes}}, {index, contexts}, hash)
       when tag_type in [:start_tag, :self_closing_tag] do
    {author_key_parts, other_attributes} = take_author_key(attributes)

    if author_key_parts do
      validate_author_key(tag_name, attributes, contexts)
    end

    {keyed_attributes, next_index} =
      if keyable_tag?(tag_name) do
        {add_slot_key(other_attributes, hash, index, author_key_parts || []), index + 1}
      else
        {attributes, index}
      end

    next_contexts = if tag_type == :start_tag, do: [:tag | contexts], else: contexts

    {{tag_type, {tag_name, keyed_attributes}}, {next_index, next_contexts}}
  end

  defp inject_slot_key({:block_start, {"for", _expr_str}} = tag, {index, contexts}, _hash) do
    {tag, {index, [:for | contexts]}}
  end

  defp inject_slot_key({:block_start, {"if", _expr_str}} = tag, {index, contexts}, _hash) do
    {tag, {index, [:if | contexts]}}
  end

  defp inject_slot_key({:block_start, "raw"} = tag, {index, contexts}, _hash) do
    {tag, {index, [:raw | contexts]}}
  end

  defp inject_slot_key(:public_comment_start = tag, {index, contexts}, _hash) do
    {tag, {index, [:comment | contexts]}}
  end

  defp inject_slot_key(tag, {index, contexts}, _hash)
       when tag == :public_comment_end or elem(tag, 0) in [:end_tag, :block_end] do
    {tag, {index, Enum.drop(contexts, 1)}}
  end

  defp inject_slot_key(tag, acc, _hash), do: {tag, acc}

  # A dynamic tag is keyed too: it renders an element whenever its expression names one. When it
  # names a component instead, the key of its place is dropped with the rest of the props the
  # component doesn't declare, and a $key the template author wrote keys the component's nodes.
  defp keyable_tag?({:expression, _templ_expr}), do: true

  defp keyable_tag?(tag_name) do
    Helpers.tag_type(tag_name) == :element and tag_name not in @unkeyable_tags
  end

  # The loop's qualifiers with its one generator binding the whole item, printed back as source, or
  # :error when the loop has no single list generator to take the item from. A trailing keyword
  # list of options prints as a list, which parses to the same AST.
  #
  # The uniq option compares what each iteration renders, so it gets no item either: binding the
  # item into every iteration would make two that render the same nodes count as different.
  defp keyed_for_qualifiers(content) do
    with {:ok, {:for, _meta, args}} <- Code.string_to_quoted("for #{content} do nil end"),
         {qualifiers, [[do: nil]]} <- Enum.split(args, -1),
         [{:<-, _meta, _args}] <- Enum.filter(qualifiers, &generator?/1),
         false <- Enum.any?(qualifiers, &uniq_option?/1) do
      {:ok, Enum.map_join(qualifiers, ", ", &Macro.to_string(bind_loop_item(&1)))}
    else
      _no_single_list_generator -> :error
    end
  end

  # A list generator, or a bitstring generator: the last part of a binary in qualifier position that
  # holds a <-, as the transformer reads it.
  defp generator?({:<-, _meta, _args}), do: true

  defp generator?({:<<>>, _meta, parts}) when is_list(parts) do
    match?({:<-, _meta, _args}, List.last(parts))
  end

  defp generator?(_qualifier), do: false

  # The value a quoted literal stands for. A literal holds no calls or variables, so evaluating it
  # runs nothing.
  # sobelow_skip ["RCE.CodeModule"]
  defp literal_value(ast) do
    ast
    |> Code.eval_quoted()
    |> elem(0)
  end

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

  defp uniq_option?(qualifier) when is_list(qualifier), do: Keyword.has_key?(qualifier, :uniq)

  defp uniq_option?(_qualifier), do: false

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

  # The text form names the ref the atom spells, so it takes only a name that can be written as an
  # atom without quotes. Any other identifier is an expression's to give. It runs when the template
  # compiles, on text the template author wrote.
  # sobelow_skip ["DOS.StringToAtom"]
  defp ref_text_atom(text) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    atom = String.to_atom(text)

    if Macro.classify_atom(atom) != :identifier do
      raise TemplateSyntaxError,
        message:
          ~s'the text form of $ref takes a plain atom name, like $ref="search", got "#{text}" - ' <>
            "write any other ref as an expression, like $ref={#{inspect(atom)}}"
    end

    case Identifier.check(atom) do
      :ok ->
        validate_ref_not_built_in(atom)
        atom

      {:error, hint} ->
        raise TemplateSyntaxError, message: Identifier.message(@ref_expectation, atom, hint)
    end
  end

  # The build judges an expression only when it's a literal built-in ref. Every other value is
  # checked when the element renders, since only then is it known.
  defp ref_value_code([text: text], _value_code) do
    "{:expression, {#{inspect(ref_text_atom(text))}}}"
  end

  defp ref_value_code([expression: expr_str], value_code) do
    case expr_str
         |> extract_expression_content()
         |> Code.string_to_quoted(emit_warnings: false) do
      {:ok, atom} when atom in @built_in_refs -> validate_ref_not_built_in(atom)
      _other -> :ok
    end

    value_code
  end

  defp ref_value_code(_value_parts, _value_code) do
    raise TemplateSyntaxError,
      message:
        ~s'the $ref attribute takes a name, like $ref="search", or a single expression, like $ref={:message, message.id}'
  end

  defp render_attribute_code({:spread, templ_expr}, _tag_type) do
    "{:spread, #{normalize_implicit_keyword_list(templ_expr)}}"
  end

  defp render_attribute_code({name, value_parts}, :element) do
    value_code = Enum.map_join(value_parts, ", ", &render_code/1)

    case decompose_event_attribute_name(name) do
      # $ref names the element for a lookup rather than something that happens to it. Its text form
      # is the atom it spells, so both renderers read one expression either way.
      {"$ref", []} ->
        "{\"$ref\", [#{ref_value_code(value_parts, value_code)}]}"

      {"$ref", [modifier | _rest]} ->
        raise TemplateSyntaxError,
          message: ~s'the $ref attribute takes no modifiers, got "#{modifier}"'

      # $data_transfer declares what a drag carries and how a drop target takes it, which the client
      # applies while the drag events run, so it binds nothing and the modifier syntax has nothing
      # to mean on it.
      {"$data_transfer", []} ->
        validate_data_transfer_value(value_parts)
        "{\"$data_transfer\", [#{value_code}]}"

      {"$data_transfer", [modifier | _rest]} ->
        raise TemplateSyntaxError,
          message: ~s'the $data_transfer attribute takes no modifiers, got "#{modifier}"'

      # $focused says where focus should be, so it is a boolean attribute the client reads rather
      # than an event binding, and the modifier syntax has nothing to mean on it.
      {"$focused", []} ->
        validate_focused_attribute_value(value_parts)
        "{\"$focused\", [#{value_code}]}"

      {"$focused", [modifier | _rest]} ->
        raise TemplateSyntaxError,
          message: ~s'the $focused attribute takes no modifiers, got "#{modifier}"'

      {base_name, []} ->
        validate_event_binding_value(base_name, value_parts)
        "{\"#{base_name}\", [#{value_code}]}"

      {base_name, modifiers} ->
        validate_event_binding_value(base_name, value_parts)
        "{\"#{base_name}\", [#{value_code}], #{render_event_modifiers(base_name, modifiers)}}"
    end
  end

  defp render_attribute_code({name, value_parts}, _tag_type) do
    "{\"#{name}\", [" <> Enum.map_join(value_parts, ", ", &render_code/1) <> "]}"
  end

  defp render_code({:block_start, "else"}) do
    "] else ["
  end

  # Each iteration renders as a loop item, which the renderers key by the item's :id. Only a loop
  # with one list generator has a single value that is the item. A loop with a bitstring generator
  # or several generators, a loop with the uniq option, or one that doesn't parse gets no item: it
  # still renders as a loop item, so that an enclosing item's key stays an outer part, and a source
  # that doesn't parse fails the build as it did before.
  defp render_code({:block_start, {"for", expr_str}}) do
    content = extract_expression_content(expr_str)

    case keyed_for_qualifiers(content) do
      {:ok, qualifiers} ->
        "(for #{qualifiers} do {:loop_item, {#{@loop_item_var}}, ["

      :error ->
        "(for #{content} do {:loop_item, nil, ["
    end
  end

  defp render_code({:block_end, "for"}) do
    "]} end)"
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
    validate_data_transfer_attributes(%DataTransfer.Unknown{}, attributes)
    validate_focus_attributes(attributes)
    validate_ref_attributes(attributes)

    attributes_code = Enum.map_join(attributes, ", ", &render_attribute_code(&1, :element))

    "{:dynamic_tag, #{templ_expr}, [#{attributes_code}], ["
  end

  defp render_code({:start_tag, {tag_name, attributes}}) do
    tag_type = Helpers.tag_type(tag_name)

    if has_ref_attribute?(attributes) do
      validate_ref_tag(tag_name, tag_type)
    end

    validate_ref_attributes(attributes)

    if tag_name in ["window", "document"] do
      validate_reserved_tag_attributes(tag_name, attributes)
    end

    if tag_type == :element do
      reserved_tag = if tag_name in ["window", "document"], do: tag_name
      validate_data_transfer_attributes(reserved_tag, attributes)

      validate_focus_attributes(attributes)
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

  defp slot_key_attribute(hash, index, author_key_parts) do
    {"$key", [{:text, "#{hash}:#{index}"} | author_key_parts]}
  end

  # Splits the $key the template author wrote off the other attributes, returning its value parts,
  # or nil when there is none. Bindings such as $key_down share the prefix but not the name.
  defp take_author_key(attributes) do
    case Enum.split_with(attributes, &author_key_attribute?/1) do
      {[], attributes} ->
        {nil, attributes}

      {[{name, value_parts}], other_attributes} ->
        validate_author_key_value(name, value_parts)
        {value_parts, other_attributes}

      {_author_keys, _other_attributes} ->
        raise TemplateSyntaxError, message: "a tag takes one $key attribute"
    end
  end

  defp author_key_attribute?({name, _value_parts}) when is_binary(name) do
    match?({"$key", _modifiers}, decompose_event_attribute_name(name))
  end

  defp author_key_attribute?(_spread), do: false

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

  # An event binding names an action or a command. A literal true names neither, and is almost
  # always $focused written as the event it is one letter away from. Only the literal is judged
  # here. An expression that evaluates to true is caught at event time on the client. False is
  # left alone: whether it should disable a binding the way nil does is a separate question.
  defp validate_event_binding_value("$" <> _rest = base_name, expression: expr_str) do
    literal = extract_expression_content(expr_str)

    if literal in ["true", ":true"] do
      hint = if base_name == "$focus", do: " - to control focus, use $focused", else: ""

      raise TemplateSyntaxError,
        message: "the #{base_name} binding takes an action or command, got #{literal}#{hint}"
    end
  end

  defp validate_event_binding_value(_name, _value_parts), do: :ok

  # A $key keys a loop item's tag, so it goes on a tag that renders straight into the loop's
  # children list, on a tag that renders a node, and not next to the cid that already is a stateful
  # component's identity.
  defp validate_author_key(tag_name, attributes, contexts) do
    unless Enum.find(contexts, &(&1 != :if)) == :for do
      raise TemplateSyntaxError, message: "$key goes on a tag directly inside a {%for} block"
    end

    if is_binary(tag_name) and tag_name in @unkeyable_tags do
      raise TemplateSyntaxError, message: "$key can't go on a <#{tag_name}> tag"
    end

    if is_binary(tag_name) and Helpers.tag_type(tag_name) == :component and
         List.keymember?(attributes, "cid", 0) do
      raise TemplateSyntaxError,
        message: "a stateful component is keyed by its cid, so it can't take $key"
    end
  end

  defp validate_author_key_value(name, value_parts) do
    case decompose_event_attribute_name(name) do
      {"$key", [modifier | _rest]} ->
        raise TemplateSyntaxError,
          message: ~s'the $key attribute takes no modifiers, got "#{modifier}"'

      {"$key", []} ->
        unless match?([expression: _expr_str], value_parts) do
          raise TemplateSyntaxError,
            message: "the $key attribute takes a single expression, like $key={item.slug}"
        end
    end
  end

  # One attribute declares it all, so a second would leave the renderers to pick between them. A
  # literal value is judged here, the way the renderers judge it, with whether the tag has a $drop
  # binding, which the value's drop effect needs, and the <window> or <document> tag it is on,
  # where no drag starts (nil for an element, %DataTransfer.Unknown{} for a dynamic tag).
  defp validate_data_transfer_attributes(tag, attributes) do
    if Enum.count(attributes, &data_transfer_attribute?/1) > 1 do
      raise TemplateSyntaxError, message: "a tag takes one $data_transfer attribute"
    end

    has_drop? = Enum.any?(attributes, &drop_attribute?/1)

    with {"$data_transfer", [expression: expr_str]} <-
           List.keyfind(attributes, "$data_transfer", 0),
         {:ok, value} <- data_transfer_literal(expr_str),
         {:error, message} <- DataTransfer.check(value, has_drop?, tag) do
      raise TemplateSyntaxError, message: message
    end

    :ok
  end

  # $data_transfer takes one expression. What it gives is judged with the tag's other attributes.
  defp validate_data_transfer_value(expression: _expr_str), do: :ok

  defp validate_data_transfer_value(_value_parts) do
    raise TemplateSyntaxError,
      message:
        "the $data_transfer attribute takes a single expression, like $data_transfer={drop_effect: :move}"
  end

  # autofocus is what $focused renders as, so an element carrying both would have the markup and
  # the state disagree about it. Only literal attributes are judged here: an autofocus arriving
  # through a spread yields to $focused at render time instead.
  defp validate_focus_attributes(attributes) do
    names = for {name, _value_parts} <- attributes, do: name

    if "autofocus" in names and "$focused" in names do
      raise TemplateSyntaxError,
        message: "an element takes either the autofocus attribute or $focused, not both"
    end
  end

  # $focused takes the value of a boolean attribute: nothing (true), or one expression.
  defp validate_focused_attribute_value(value_parts)

  defp validate_focused_attribute_value([]), do: :ok

  defp validate_focused_attribute_value(expression: _expr_str), do: :ok

  defp validate_focused_attribute_value(_value_parts) do
    raise TemplateSyntaxError,
      message: "the $focused attribute takes a single expression, like $focused={@editing?}"
  end

  defp validate_ref_attributes(attributes) do
    if Enum.count(attributes, &ref_attribute?/1) > 1 do
      raise TemplateSyntaxError, message: "a tag takes one $ref attribute"
    end
  end

  defp has_ref_attribute?(attributes), do: Enum.any?(attributes, &ref_attribute?/1)

  defp ref_attribute?({name, _value_parts}) when is_binary(name) do
    match?({"$ref", _modifiers}, decompose_event_attribute_name(name))
  end

  defp ref_attribute?(_spread), do: false

  # :window and :document name the window and the document, which no template renders.
  defp validate_ref_not_built_in(:window) do
    raise TemplateSyntaxError,
      message:
        ":window is a built-in ref, so a template can't name an element with it - JS.element(:window) returns the window"
  end

  defp validate_ref_not_built_in(:document) do
    raise TemplateSyntaxError,
      message:
        ":document is a built-in ref, so a template can't name an element with it - JS.element(:document) returns the document"
  end

  defp validate_ref_not_built_in(_atom), do: :ok

  # A ref names an element, so it goes only on a tag that renders one the client can reach. The
  # client patches the <html> element's attributes through a node of its own rather than the
  # rendered one, so a ref there would name nothing.
  defp validate_ref_tag(tag_name, :component) do
    raise TemplateSyntaxError,
      message:
        "$ref can't go on the <#{tag_name}> component tag - a component renders no element of its own, " <>
          "so put $ref on an element in its template and pass the ref as a prop, like input_ref={:search}"
  end

  defp validate_ref_tag(tag_name, _tag_type) when tag_name in ["window", "document"] do
    raise TemplateSyntaxError,
      message:
        "$ref can't go on a <#{tag_name}> tag, which renders no element - JS.element(:#{tag_name}) returns the #{tag_name}"
  end

  defp validate_ref_tag("slot", _tag_type) do
    raise TemplateSyntaxError,
      message:
        "$ref can't go on a <slot> tag, which renders no element of its own - put it on an element in the slot content"
  end

  defp validate_ref_tag("html", _tag_type) do
    raise TemplateSyntaxError,
      message:
        "$ref can't go on the <html> tag - JS.element(:document) returns the document, whose documentElement is the <html> element"
  end

  defp validate_ref_tag(_tag_name, _tag_type), do: :ok

  # The <window> and <document> tags bind events to the window or document and nothing else, so each
  # attribute must be an event binding (a "$"-prefixed name). Any other attribute fails the build.
  # $focused is "$"-prefixed and still not a binding: there is no element for it to focus.
  defp validate_reserved_tag_attributes(tag_name, attributes) do
    Enum.each(attributes, fn
      # Spread entries can't carry event bindings, since "$"-prefixed keys are rejected at runtime.
      {:spread, _templ_expr} ->
        raise TemplateSyntaxError,
          message: ~s'the <#{tag_name}> tag accepts only event bindings, but got a spread'

      {name, _value_parts} ->
        {base_name, _modifiers} = decompose_event_attribute_name(name)

        unless String.starts_with?(name, "$") and base_name != "$focused" do
          raise TemplateSyntaxError,
            message:
              ~s'the <#{tag_name}> tag accepts only event bindings, but got the "#{name}" attribute'
        end
    end)
  end
end
