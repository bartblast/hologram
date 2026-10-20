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

  @range_operators [:.., :..//]

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

  @spec operand_error!(String.t(), Macro.t(), Macro.Env.t()) :: no_return
  defp operand_error!(subject, ast, env) do
    compile_error!(
      "#{subject} is a literal or a pinned expression, got: #{Macro.to_string(ast)} - a value from the surrounding code is pinned: #{pin_hint(ast)}",
      ast,
      env
    )
  end

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
end
