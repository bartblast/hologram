defmodule Hologram.Policy.Expression do
  @moduledoc false

  # Lowers what an allow line was written with to the data form Hologram.Entity.__put_policy__/4
  # stores. Every key on the line is an option - to: names who holds the operation, via: the
  # relationship it is delegated through, when: the condition - so no attribute name is taken by
  # the line. Roles are atoms, relationships are bare names, the condition is an expression, and
  # anything from the surrounding code is pinned with ^.
  #
  # It runs at expansion and judges the spelling only. Whether a role, a relationship or an
  # attribute is declared stays with the declaration and the whole-model validation, which judge
  # the data the line evaluated to.

  alias Hologram.Query.Expression, as: QueryExpression

  @delegation_names %{stage: "via", names: "a relationship", spelled: "a bare name"}

  @doc """
  Lowers the options argument of an `allow` line, written for the given operation, to the AST of
  the keyword list `Hologram.Entity.__put_policy__/4` takes.

  `to:` keeps role names and role modules, lowers a `{role, relationship}` tuple's bare name to an
  atom (`{:editor, project}` to `{:editor, :project}`) and keeps a `{role, entity type}` tuple, in
  a list or alone. `via:` lowers a bare name to an atom. `when:` lowers through
  `Hologram.Query.Expression.condition/2`. A pinned `to:`, `via:` or `when:` value, a pinned
  element of a `to:` list and a pinned role or scope of a tuple lower to the expression.
  `__MODULE__` names a module wherever a module goes. A nil `to:` or `via:` value and a list
  element that is not a keyword entry pass through for the declaration to refuse.

  Raises Hologram.CompileError, located at the offending node, on options not written in place, on
  an unknown option (naming the condition it can mean when its value is an equality operand), on a
  grant reference with the scope first or a relationship written as an atom, on a role written as
  a bare name, on a delegation written as an atom or as a path, and on anything else.
  """
  @spec spec(Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def spec(operation, spec, env) when is_list(spec) do
    Enum.map(spec, &option!(&1, operation, env))
  end

  def spec(operation, spec, env) do
    QueryExpression.compile_error!(
      "allow #{Macro.to_string(operation)} takes a keyword list of options written in place, got: #{Macro.to_string(spec)}",
      spec,
      env
    )
  end

  # __MODULE__ has the shape of a bare name, but it names the module it is written in.
  defp bare_name?({:__MODULE__, _meta, _context}), do: false

  defp bare_name?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true

  defp bare_name?(_ast), do: false

  # One hop, as the delegation has always been - a path reaches further than the target's own
  # policy, which is a change to what delegation means rather than a spelling.
  defp delegation!(nil, _env), do: nil

  defp delegation!({:__MODULE__, _meta, _context} = ast, env) do
    QueryExpression.compile_error!(
      "via names a relationship with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
      ast,
      env
    )
  end

  defp delegation!(ast, env) do
    case QueryExpression.hops(ast) do
      [_hop, _next_hop | _later_hops] ->
        QueryExpression.compile_error!(
          "via takes one relationship, got: #{Macro.to_string(ast)}",
          ast,
          env
        )

      _one_hop_or_none ->
        QueryExpression.name!(ast, @delegation_names, env)
    end
  end

  # A value an unknown option can be read as an equality with - anything else (an operator tuple,
  # a list) meant another operator, and an equality hint would mislead.
  defp equality_operand?({:^, _meta, [_expr]}), do: true

  defp equality_operand?({:user_id, _meta, []}), do: true

  defp equality_operand?(value), do: literal?(value)

  defp grant_reference!({:^, _meta, [expr]}, _env), do: expr

  defp grant_reference!(atom, _env) when is_atom(atom), do: atom

  defp grant_reference!({:__aliases__, _meta, _segments} = ast, _env), do: ast

  defp grant_reference!({:__MODULE__, _meta, context} = ast, _env) when is_atom(context), do: ast

  defp grant_reference!({name, _meta, context} = ast, env)
       when is_atom(name) and is_atom(context) do
    QueryExpression.compile_error!(
      "to names a role with an atom, got: #{name} - write #{inspect(name)}",
      ast,
      env
    )
  end

  defp grant_reference!({role, scope} = ast, env) do
    cond do
      scope_first?(ast) ->
        QueryExpression.compile_error!(
          "the role comes first in a grant reference, got: #{Macro.to_string(ast)} - write #{Macro.to_string({scope, role})}",
          ast,
          env
        )

      role?(role) ->
        {role_value(role), reference_scope!(ast, env)}

      true ->
        reference_error!(ast, env)
    end
  end

  defp grant_reference!(ast, env), do: reference_error!(ast, env)

  defp grant_references!({:^, _meta, [expr]}, _env), do: expr

  defp grant_references!(list, env) when is_list(list),
    do: Enum.map(list, &grant_reference!(&1, env))

  defp grant_references!(ast, env), do: grant_reference!(ast, env)

  # An atom (nil, true and false included), a number, a string, a module name, or a number with a
  # sign.
  defp literal?(value) when is_atom(value) or is_number(value) or is_binary(value), do: true

  defp literal?({:__aliases__, _meta, _segments}), do: true

  defp literal?({sign, _meta, [number]}) when sign in [:+, :-] and is_number(number), do: true

  defp literal?(_value), do: false

  defp module?({:__aliases__, _meta, _segments}), do: true

  defp module?({:__MODULE__, _meta, context}) when is_atom(context), do: true

  defp module?(_ast), do: false

  defp name_atom?(atom), do: is_atom(atom) and atom not in [nil, true, false]

  defp option!({:to, value}, _operation, env), do: {:to, grant_references!(value, env)}

  defp option!({:via, value}, _operation, env), do: {:via, delegation!(value, env)}

  defp option!({:when, value}, _operation, env),
    do: {:when, QueryExpression.condition(value, env)}

  defp option!({key, value}, operation, env) when is_atom(key),
    do: unknown_option!(key, value, operation, env)

  defp option!(element, _operation, _env), do: element

  @spec reference_error!(Macro.t(), Macro.Env.t()) :: no_return
  defp reference_error!(ast, env) do
    QueryExpression.compile_error!(
      "to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  # The scope of a grant reference: a module names an entity type and stays, a bare name names a
  # relationship and lowers to its atom. A relationship written as an atom is the old spelling,
  # refused with the bare one.
  defp reference_scope!({_role, {:^, _meta, [expr]}}, _env), do: expr

  defp reference_scope!({_role, {:__aliases__, _meta, _segments} = scope}, _env), do: scope

  defp reference_scope!({_role, {:__MODULE__, _meta, context} = scope}, _env)
       when is_atom(context),
       do: scope

  defp reference_scope!({_role, {name, _meta, context}}, _env)
       when is_atom(name) and is_atom(context),
       do: name

  # Two atoms are also the order the tuple had before it turned around, {:project, :editor}, so
  # nothing says which one is the role - the message names the shape rather than a rewrite that
  # could swap them.
  defp reference_scope!({_role, scope} = ast, env) do
    if name_atom?(scope) do
      QueryExpression.compile_error!(
        "to names a relationship with a bare name and puts the role first, got: #{Macro.to_string(ast)} - write {role, relationship}, like {:editor, project}",
        ast,
        env
      )
    else
      reference_error!(ast, env)
    end
  end

  defp role?({:^, _meta, [_expr]}), do: true

  defp role?(role), do: name_atom?(role)

  defp role_value({:^, _meta, [expr]}), do: expr

  defp role_value(role), do: role

  # The scope written where the role goes: a relationship or an entity type first and a role atom
  # second is the order the tuple had before it turned around.
  defp scope_first?({first, second}) do
    (bare_name?(first) or module?(first)) and name_atom?(second)
  end

  @spec unknown_option!(atom, Macro.t(), Macro.t(), Macro.Env.t()) :: no_return
  defp unknown_option!(key, value, operation, env) do
    hint =
      if equality_operand?(value) do
        condition = Macro.to_string({:==, [], [{key, [], nil}, value]})

        ", and a condition goes in when: #{condition}"
      else
        ""
      end

    QueryExpression.compile_error!(
      "unknown option #{inspect(key)} for allow #{Macro.to_string(operation)} - the allow options are to, via and when#{hint}",
      value,
      env
    )
  end
end
