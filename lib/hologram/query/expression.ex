defmodule Hologram.Query.Expression do
  @moduledoc false

  # Lowers what a query stage was written with to the data form Hologram.Query.Stage takes. Inside
  # a query a bare name is something the entity declares, and anything from the surrounding Elixir
  # code is pinned with ^ - so the lowering reads names as names and passes a pinned expression
  # through as the caller's code, evaluated where the stage is called. Literals need nothing.
  #
  # It runs at expansion, before the queried entity is known (a stage may be called on a query
  # held in a variable), so it judges the spelling only. Whether a name is declared, and whether a
  # value suits it, stays with the stage, which judges the data it is given.

  @comparison_operators [:!=, :<, :<=, :==, :>, :>=]

  @inclusion_names %{stage: "include", names: "a relationship", spelled: "a bare name or a path"}

  @ordering_names %{stage: "order_by", names: "an attribute", spelled: "a bare name"}

  @range_operators [:.., :..//]

  @doc """
  Lowers the bound argument of `limit/2` or `offset/2`, named by the given stage, to what the
  stage function takes: an integer literal, or the pinned expression itself.

  Raises Hologram.CompileError, located at the argument, on anything else.
  """
  @spec bound(Macro.t(), atom, Macro.Env.t()) :: Macro.t()
  def bound({:^, _meta, [expr]}, _stage, _env), do: expr

  def bound(ast, stage, env) do
    if integer_literal?(ast) do
      ast
    else
      compile_error!(
        "#{stage} takes an integer or a pinned expression, got: #{Macro.to_string(ast)}#{pin_suffix(ast)}",
        ast,
        env
      )
    end
  end

  @doc """
  Lowers the spec argument of `include/2` to the AST of what `Hologram.Query.Stage.include/2`
  takes: a relationship name, or a shape list of names, `{name, nested_spec}` pairs and
  `{name, sub_builder}` pairs.

  A relationship is a bare name (`owner`) and a nested one a path (`tasks.owner`), lowering to
  `:owner` and `[tasks: [:owner]]`. A list holds names, paths, pinned elements and, last, keyword
  entries pairing a relationship with a sub-builder written in place or pinned
  (`[owner, tasks.owner, project: &open/1]`). Paths sharing a first hop merge in the order they
  first appear, so `[tasks.owner, tasks.project]` lowers to `[tasks: [:owner, :project]]`, and a
  bare name beside a path through it is absorbed by the path. A pinned spec passes through.

  Raises Hologram.CompileError, located at the offending node, on an atom where a bare name goes
  (naming the bare spelling), on a keyword entry nesting a name or a list (naming the path), and
  on anything else.
  """
  @spec inclusion(Macro.t(), Macro.Env.t()) :: Macro.t()
  def inclusion({:^, _meta, [expr]}, _env), do: expr

  def inclusion(list, env) when is_list(list) do
    list
    |> Enum.map(&include_element!(&1, env))
    |> merge_includes()
  end

  def inclusion(ast, env) do
    case include_element!(ast, env) do
      {:path, [name]} -> name
      element -> merge_includes([element])
    end
  end

  @doc """
  Lowers the spec argument of `order_by/2` to the AST of what `Hologram.Query.Stage.order_by/2`
  takes: an attribute name, or a list of names and `{name, direction}` pairs.

  An attribute is a bare name (`priority`), lowering to `:priority`. A list holds names and pairs,
  keyword syntax included (`[title, priority: :desc]`), a direction is an atom or pinned, and a
  name or the whole spec may be pinned.

  Raises Hologram.CompileError, located at the offending node, on an atom where a bare name goes
  (naming the bare spelling), on a direction that is neither an atom nor pinned, and on anything
  else in a name position.
  """
  @spec ordering(Macro.t(), Macro.Env.t()) :: Macro.t()
  def ordering({:^, _meta, [expr]}, _env), do: expr

  def ordering(list, env) when is_list(list), do: Enum.map(list, &ordering_entry!(&1, env))

  def ordering(ast, env), do: name!(ast, @ordering_names, env)

  @doc """
  Lowers the options argument of `paginate/2` to what the stage function takes: a keyword list
  whose values are integer literals or pinned, or the pinned expression itself. The option names
  are the stage's to judge.

  Raises Hologram.CompileError, located at the offending node, on anything else.
  """
  @spec pagination(Macro.t(), Macro.Env.t()) :: Macro.t()
  def pagination({:^, _meta, [expr]}, _env), do: expr

  def pagination(list, env) when is_list(list), do: Enum.map(list, &pagination_option!(&1, env))

  def pagination(ast, env), do: pagination_error!(ast, env)

  @doc """
  Lowers the predicates argument of `filter/2` to the AST of what `Hologram.Query.Stage.filter/2`
  takes: a keyword list of attribute names and operator tuples, or the pinned expression itself.

  Accepts a pinned expression (`^predicates`), a keyword list of equalities whose values are
  literals or pinned (`project_id: ^project_id, status: :todo`), a comparison of a bare attribute
  name with a literal or a pinned value (`==`, `!=`, `<`, `<=`, `>`, `>=`), membership in a list
  literal, a range literal or a pinned expression (`in`), negated membership in a list literal or
  a pinned expression (`not in`), and comparisons and memberships joined with `and`.

  Raises Hologram.CompileError, located at the offending node, on anything else.
  """
  @spec predicates(Macro.t(), Macro.Env.t()) :: Macro.t()
  def predicates({:^, _meta, [expr]}, _env), do: expr

  def predicates(list, env) when is_list(list), do: Enum.map(list, &keyword_entry!(&1, env))

  def predicates(ast, env), do: predicate_list!(ast, env)

  @doc """
  Lowers the relationship argument of `include/3` to the list of its hops: `[:owner]` for a bare
  name, `[:project, :tasks]` for a path, and the pinned expression alone in a list for a pinned
  name.

  Raises Hologram.CompileError, located at the argument, on an atom where a bare name goes and on
  anything else that is neither a name nor a path.
  """
  @spec relationship(Macro.t(), Macro.Env.t()) :: list(Macro.t())
  def relationship({:^, _meta, [expr]}, _env), do: [expr]

  def relationship(ast, env), do: hops(ast) || name_error!(ast, @inclusion_names, env)

  @doc """
  Lowers the sub-builder argument of `include/3`: a function written in place (`fn` or a capture)
  passes through, and a pinned expression lowers to the expression.

  Raises Hologram.CompileError, located at the argument, on anything else.
  """
  @spec sub_builder(Macro.t(), Macro.Env.t()) :: Macro.t()
  def sub_builder({:^, _meta, [expr]}, _env), do: expr

  def sub_builder(ast, env) do
    if in_place_function?(ast) do
      ast
    else
      compile_error!(
        "include/3 takes a sub-builder written in place (fn or &) or a pinned expression, got: #{Macro.to_string(ast)}#{pin_suffix(ast)}",
        ast,
        env
      )
    end
  end

  # A path joins the slot of its first hop, or opens one where it first appears - so paths sharing
  # a first hop merge, a bare name is a path with no tail, and elements that are not paths keep
  # their place. The slots are held newest first, and merge_includes/1 reverses them.
  defp add_include_path(slots, hop, tail) do
    case Enum.find_index(slots, &match?({:path_group, ^hop, _tails}, &1)) do
      nil ->
        [{:path_group, hop, tails_of(tail)} | slots]

      index ->
        List.update_at(slots, index, fn {:path_group, ^hop, tails} ->
          {:path_group, hop, tails ++ tails_of(tail)}
        end)
    end
  end

  defp attribute!({name, _meta, context}, _env) when is_atom(name) and is_atom(context), do: name

  defp attribute!(ast, env) do
    compile_error!(
      "the left side of a comparison names an attribute of the queried entity, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp bare_name?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true

  defp bare_name?(_ast), do: false

  @spec compile_error!(String.t(), Macro.t(), Macro.Env.t()) :: no_return
  defp compile_error!(message, ast, env) do
    raise Hologram.CompileError, message: message, file: env.file, line: line(ast, env)
  end

  # A keyword list and a pinned list are each a whole filter, so neither is one side of an and -
  # the stage it would be joined to is a second filter call.
  defp conjunct!(ast, env) when is_list(ast), do: whole_filter_conjunct!(ast, env)

  defp conjunct!({:^, _meta, [_expr]} = ast, env), do: whole_filter_conjunct!(ast, env)

  defp conjunct!(ast, env), do: predicate_list!(ast, env)

  # The shapes a keyword value took in the data form: an operator tuple, a membership list, a range.
  defp data_form?({operator, _operand}) when is_atom(operator), do: true

  defp data_form?({:{}, _meta, _elems}), do: true

  defp data_form?(list) when is_list(list), do: true

  defp data_form?({operator, _meta, _bounds}) when operator in @range_operators, do: true

  defp data_form?(_value), do: false

  defp direction!({:^, _meta, [expr]}, _env), do: expr

  defp direction!(direction, _env) when is_atom(direction), do: direction

  defp direction!(ast, env) do
    compile_error!(
      "a direction is :asc, :desc or a pinned expression, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  # The expression a data-form keyword value is spelled as - concrete where the shape says which
  # operator it is, generic where it does not.
  defp expression_hint(key, {operator, operand}) when operator in @comparison_operators do
    written_as({operator, [], [{key, [], nil}, operand]})
  end

  defp expression_hint(key, {:in, operand}) do
    written_as({:in, [], [{key, [], nil}, operand]})
  end

  defp expression_hint(key, {:not_in, operand}) do
    written_as({:not, [], [{:in, [], [{key, [], nil}, operand]}]})
  end

  defp expression_hint(key, list) when is_list(list) do
    written_as({:in, [], [{key, [], nil}, list]})
  end

  defp expression_hint(key, {operator, _meta, _bounds} = range)
       when operator in @range_operators do
    written_as({:in, [], [{key, [], nil}, range]})
  end

  defp expression_hint(_key, _value) do
    "a comparison, a membership or a range is written as an expression"
  end

  @spec forgotten_pin!(Macro.t(), Macro.Env.t()) :: no_return
  defp forgotten_pin!({name, _meta, _context} = ast, env) do
    compile_error!(
      "#{name} reads as an attribute of the queried entity, and an attribute is compared only with a value - a value from the surrounding code is pinned: ^#{name}",
      ast,
      env
    )
  end

  # The relationships a bare name or a path names, in order - nil for anything else. A path is a
  # dot chain with no parentheses over a bare name, so a call (`tasks.owner()`, `Foo.bar`) is not
  # one.
  defp hops(ast) do
    case reversed_hops(ast) do
      nil -> nil
      reversed -> Enum.reverse(reversed)
    end
  end

  defp in_place_function?({:fn, _meta, _clauses}), do: true

  defp in_place_function?({:&, _meta, _args}), do: true

  defp in_place_function?(_ast), do: false

  # A list element of an include spec: a pinned element keeps its place, a keyword entry pairs a
  # relationship with a sub-builder, and a bare name or a path joins the merge.
  defp include_element!({:^, _meta, [expr]}, _env), do: {:in_place, expr}

  defp include_element!({key, {:^, _meta, [expr]}}, _env) when is_atom(key),
    do: {:in_place, {key, expr}}

  # A keyword entry pairs a relationship with a sub-builder. A value naming relationships is a
  # nesting attempt, refused with the paths it means, and anything else a sub-builder missing its
  # pin.
  defp include_element!({key, value}, env) when is_atom(key) do
    if in_place_function?(value) do
      {:in_place, {key, value}}
    else
      case written_paths(key, value) do
        nil -> keyword_sub_builder_error!(key, value, env)
        paths -> nested_include_error!(key, value, paths, env)
      end
    end
  end

  defp include_element!(ast, env) do
    case hops(ast) do
      nil -> name_error!(ast, @inclusion_names, env)
      hops -> {:path, hops}
    end
  end

  # An integer, or one with a sign - a signed number is a call in the AST, but reads as a literal.
  defp integer_literal?(value) when is_integer(value), do: true

  defp integer_literal?({sign, _meta, [number]}) when sign in [:+, :-] and is_integer(number),
    do: true

  defp integer_literal?(_ast), do: false

  defp keyword_entry!({key, value}, env) when is_atom(key) do
    {key, {:==, keyword_value!(key, value, env)}}
  end

  defp keyword_entry!({_key, _value} = entry, env) do
    compile_error!(
      "a keyword predicate names an attribute with an atom, got: #{Macro.to_string(entry)}",
      entry,
      env
    )
  end

  defp keyword_entry!(entry, env) do
    compile_error!(
      "a keyword predicate is attribute: value, got: #{Macro.to_string(entry)}#{listed_comparison_hint(entry)}",
      entry,
      env
    )
  end

  @spec keyword_sub_builder_error!(atom, Macro.t(), Macro.Env.t()) :: no_return
  defp keyword_sub_builder_error!(key, value, env) do
    compile_error!(
      "a keyword entry in include pairs a relationship with a sub-builder written in place (fn or &) or a pinned expression, got: #{Macro.to_string([{key, value}])}#{pin_suffix(value)}",
      value,
      env
    )
  end

  # A keyword predicate means equality, so the data form's other shapes are refused where they are
  # written, with the expression that says the same thing. Only a written-out value is judged: a
  # pinned one is an equality operand whatever it holds, and the stage refuses one that can't be.
  defp keyword_value!(_key, {:^, _meta, [expr]}, _env), do: expr

  defp keyword_value!(key, value, env) do
    cond do
      literal?(value) ->
        value

      bare_name?(value) ->
        forgotten_pin!(value, env)

      data_form?(value) ->
        compile_error!(
          "a keyword predicate is an equality, got: #{Macro.to_string([{key, value}])} - #{expression_hint(key, value)}",
          value,
          env
        )

      true ->
        operand_error!("a keyword predicate value", value, env)
    end
  end

  defp line({_name, meta, _args}, env) when is_list(meta), do: Keyword.get(meta, :line, env.line)

  defp line(_ast, env), do: env.line

  defp listed_comparison_hint({operator, _meta, [_left, _right]})
       when operator in @comparison_operators or operator in [:in, :not] do
    " - join comparisons with and"
  end

  defp listed_comparison_hint(_entry), do: ""

  # An atom (nil, true and false included), a number, a string, a module name, or a number with a
  # sign - a signed number is a call in the AST, but reads, and evaluates, as a literal.
  defp literal?(value) when is_atom(value) or is_number(value) or is_binary(value), do: true

  defp literal?({:__aliases__, _meta, _segments}), do: true

  defp literal?({sign, _meta, [number]}) when sign in [:+, :-] and is_number(number), do: true

  defp literal?(_value), do: false

  defp membership!({:^, _meta, [expr]}, _env), do: expr

  defp membership!(list, env) when is_list(list) do
    Enum.map(list, &value!(&1, "a membership element", env))
  end

  defp membership!({operator, meta, bounds}, env) when operator in @range_operators do
    {operator, meta, Enum.map(bounds, &value!(&1, "a range bound", env))}
  end

  defp membership!(ast, env) do
    compile_error!(
      "a membership operand is a list, a range or a pinned expression, got: #{Macro.to_string(ast)} - a value from the surrounding code is pinned: #{pin_hint(ast)}",
      ast,
      env
    )
  end

  defp merge_includes(elements) do
    elements
    |> Enum.reduce([], fn
      {:path, [hop | tail]}, slots -> add_include_path(slots, hop, tail)
      {:in_place, ast}, slots -> [{:in_place, ast} | slots]
    end)
    |> Enum.reverse()
    |> Enum.map(fn
      {:in_place, ast} -> ast
      {:path_group, hop, []} -> hop
      {:path_group, hop, tails} -> {hop, merge_includes(Enum.map(tails, &{:path, &1}))}
    end)
  end

  defp name!({:^, _meta, [expr]}, _names, _env), do: expr

  defp name!({name, _meta, context}, _names, _env) when is_atom(name) and is_atom(context),
    do: name

  defp name!(ast, names, env), do: name_error!(ast, names, env)

  # An atom where a bare name goes is the old spelling, refused with the new one - other than nil,
  # true and false, which name nothing.
  @spec name_error!(Macro.t(), map, Macro.Env.t()) :: no_return
  defp name_error!(atom, names, env) when is_atom(atom) and atom not in [nil, true, false] do
    compile_error!(
      "#{names.stage} names #{names.names} with a bare name, got: #{inspect(atom)} - write #{atom}",
      atom,
      env
    )
  end

  defp name_error!(ast, names, env) do
    compile_error!(
      "#{names.stage} names #{names.names} with #{names.spelled}, or with a pinned expression when the name comes from the surrounding code, got: #{Macro.to_string(ast)}#{pin_suffix(ast)}",
      ast,
      env
    )
  end

  # The data form has no negated range, so a range here could only fail when the query is built,
  # in words about an operator nobody wrote.
  defp negated_membership!({operator, _meta, _bounds} = ast, env)
       when operator in @range_operators do
    compile_error!(
      "a negated membership takes a list or a pinned expression, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp negated_membership!(ast, env), do: membership!(ast, env)

  @spec nested_include_error!(atom, Macro.t(), list(String.t()), Macro.Env.t()) :: no_return
  defp nested_include_error!(key, value, paths, env) do
    hint =
      case paths do
        [path] -> "write it as a path: #{path}"
        paths -> "write each as a path: #{Enum.join(paths, ", ")}"
      end

    compile_error!(
      "include nests with a path, got: #{Macro.to_string([{key, value}])} - #{hint}",
      value,
      env
    )
  end

  @spec operand_error!(String.t(), Macro.t(), Macro.Env.t()) :: no_return
  defp operand_error!(subject, ast, env) do
    compile_error!(
      "#{subject} is a literal or a pinned expression, got: #{Macro.to_string(ast)} - a value from the surrounding code is pinned: #{pin_hint(ast)}",
      ast,
      env
    )
  end

  defp option_value!({:^, _meta, [expr]}, _env), do: expr

  defp option_value!(ast, env) do
    if integer_literal?(ast) do
      ast
    else
      compile_error!(
        "a paginate option takes an integer or a pinned expression, got: #{Macro.to_string(ast)}#{pin_suffix(ast)}",
        ast,
        env
      )
    end
  end

  # An atom key is keyword syntax (`priority: :desc`), which cannot be told from a written-out
  # `{:priority, :desc}`, so a pair's key is an atom or a name.
  defp ordering_entry!({key, direction}, env) do
    {ordering_key!(key, env), direction!(direction, env)}
  end

  defp ordering_entry!(ast, env), do: name!(ast, @ordering_names, env)

  defp ordering_key!(key, _env) when is_atom(key), do: key

  defp ordering_key!(ast, env), do: name!(ast, @ordering_names, env)

  @spec pagination_error!(Macro.t(), Macro.Env.t()) :: no_return
  defp pagination_error!(ast, env) do
    compile_error!(
      "paginate takes page: and size: options or a pinned expression, got: #{Macro.to_string(ast)}#{pin_suffix(ast)}",
      ast,
      env
    )
  end

  defp pagination_option!({key, value}, env) when is_atom(key),
    do: {key, option_value!(value, env)}

  defp pagination_option!(entry, env), do: pagination_error!(entry, env)

  # ^ binds looser than a call or a dot, and tighter than any other operator, so only an operator
  # expression needs parentheses to be pinned whole. A module attribute reads as a name: ^@max.
  defp pin_hint({operator, _meta, args} = ast)
       when is_atom(operator) and is_list(args) and operator != :@ do
    if Macro.operator?(operator, length(args)) do
      "^(#{Macro.to_string(ast)})"
    else
      "^#{Macro.to_string(ast)}"
    end
  end

  defp pin_hint(ast), do: "^#{Macro.to_string(ast)}"

  defp pin_suffix(ast) do
    if literal?(ast) do
      ""
    else
      " - a value from the surrounding code is pinned: #{pin_hint(ast)}"
    end
  end

  defp predicate_list!({:and, _meta, [left, right]}, env) do
    conjunct!(left, env) ++ conjunct!(right, env)
  end

  defp predicate_list!({:not, _meta, [{:in, _in_meta, [left, right]}]}, env) do
    [{attribute!(left, env), {:not_in, negated_membership!(right, env)}}]
  end

  defp predicate_list!({:in, _meta, [left, right]}, env) do
    [{attribute!(left, env), {:in, membership!(right, env)}}]
  end

  defp predicate_list!({operator, _meta, [left, right]}, env)
       when operator in @comparison_operators do
    [{attribute!(left, env), {operator, value!(right, "a comparison operand", env)}}]
  end

  defp predicate_list!(ast, env), do: unsupported!(ast, env)

  defp reversed_hops({name, _meta, context}) when is_atom(name) and is_atom(context), do: [name]

  defp reversed_hops({{:., _dot_meta, [left, field]}, meta, []}) when is_atom(field) do
    with true <- Keyword.get(meta, :no_parens, false),
         [_hop | _rest] = left_hops <- reversed_hops(left) do
      [field | left_hops]
    else
      _not_a_path -> nil
    end
  end

  defp reversed_hops(_ast), do: nil

  defp tails_of([]), do: []

  defp tails_of(tail), do: [tail]

  @spec unsupported!(Macro.t(), Macro.Env.t()) :: no_return
  defp unsupported!(ast, env) do
    compile_error!(
      "unsupported expression in a filter: #{Macro.to_string(ast)} - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, a keyword list of equalities, or a pinned list of predicates",
      ast,
      env
    )
  end

  defp value!({:^, _meta, [expr]}, _subject, _env), do: expr

  defp value!(ast, subject, env) do
    cond do
      literal?(ast) -> ast
      bare_name?(ast) -> forgotten_pin!(ast, env)
      true -> operand_error!(subject, ast, env)
    end
  end

  @spec whole_filter_conjunct!(Macro.t(), Macro.Env.t()) :: no_return
  defp whole_filter_conjunct!(ast, env) do
    compile_error!(
      "a keyword list or a pinned list of predicates is a whole filter, not one side of and, got: #{Macro.to_string(ast)} - pass it to a filter call of its own",
      ast,
      env
    )
  end

  defp written_as(expression), do: "write it as an expression: #{Macro.to_string(expression)}"

  # The paths a keyword value naming relationships would be written as - nil when the value names
  # anything else.
  defp written_paths(prefix, atom) when is_atom(atom) and atom not in [nil, true, false],
    do: ["#{prefix}.#{atom}"]

  defp written_paths(prefix, [_element | _rest] = list) do
    paths = Enum.map(list, &written_paths(prefix, &1))

    if Enum.any?(paths, &is_nil/1), do: nil, else: List.flatten(paths)
  end

  defp written_paths(prefix, {key, value}) when is_atom(key),
    do: written_paths("#{prefix}.#{key}", value)

  defp written_paths(prefix, ast) do
    case hops(ast) do
      nil -> nil
      hops -> [Enum.join([prefix | hops], ".")]
    end
  end
end
