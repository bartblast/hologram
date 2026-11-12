defmodule Hologram.Entity.DerivedExpression do
  @moduledoc false

  # Lowers the function of a derived field to the body its definition function runs. The function's
  # arguments name fields of the row, which has no values while the definition is built, so every
  # place the body reads one is rewritten to Hologram.Entity.Derived.field/2 - a stand-in that
  # becomes a query over the row's set, a name of the row in a condition, or a row to read further
  # through. What the body computes with them is rewritten to the Derived calls that build a
  # definition: <> to concat/1, if to if_value/3, and a condition to condition/2, its comparisons
  # lowered to the filter data form here, so Stage judges them at resolution as it judges a filter.
  #
  # Inside a query a bare name is the queried row's, so the rewrite reads the body in two modes: an
  # Elixir position (the body, a stage's source, a pinned expression) reads the arguments, a query
  # position (a stage's other arguments, outside a pin) is left to the Hologram.Query macros as
  # written.
  #
  # A derived field is computed by the database, so anything else is refused at its line: Elixir
  # over a row is a plain def in the module. A def a derived body calls is a query builder, held to
  # the query vocabulary by the build's walk.

  alias Hologram.Entity.Derived
  alias Hologram.Query.Expression

  @comparison_operators [:!=, :<, :<=, :==, :>, :>=]

  # The applications shipped with Elixir itself - a call into one computes in Elixir, never in a
  # query, and so does a call into an Erlang module.
  @elixir_apps [:eex, :elixir, :ex_unit, :iex, :logger, :mix]

  # Forms that are no call, named as written rather than by an arity.
  @special_forms [
    :%,
    :%{},
    :&,
    :<<>>,
    :^,
    :__block__,
    :case,
    :cond,
    :fn,
    :for,
    :quote,
    :receive,
    :try,
    :unless,
    :unquote,
    :with,
    :{}
  ]

  # The meta key marking a call to the module's own function, a query builder the module must
  # define - whether it does is known only once the module body has run, so the mark is what
  # validate_own_builders!/1 looks for then. Its value is where the call stands, :query or :scalar.
  @own_builder_key :hologram_own_builder

  # The query stages a derived body reads its rows with, by the number of arguments each takes.
  @stages [count: 1, filter: 2, include: 2, one: 1, skip: 2, sort: 2, take: 2]

  @vocabulary_reason "a derived field is query vocabulary, evaluated by the database - Elixir over a row is a plain def in the module, called where the row is used"

  @doc """
  Lowers the given derived field's function to the names its head binds, the body its definition
  function runs and whether that body calls a query builder - a function of another module, of a
  module the entity type imports it from, or of the entity type's own.

  An argument read in the body becomes a `Hologram.Entity.Derived.field/2` call naming the field, a
  dot chain on one names the path, a pipe is unpiped, a module attribute an unquote fragment reading
  its value where the body is escaped with `unquote: true`, and an alias its module. `<>` becomes
  `Derived.concat/1` over its flattened operands, `if` becomes `Derived.if_value/3`, and a condition
  - the whole body, or the condition of `if` - becomes `Derived.condition/2` over its comparisons in
  the filter data form.

  A local call named like a query stage is that stage, and any other is a query builder of the
  entity type's own, which validate_own_builders!/1 checks the module defines once its body has run.

  Raises Hologram.CompileError, located at the offending node, on anything else: a local binding, a
  call into Elixir's or Erlang's own modules, an imported one included, a function of
  Hologram.Query that is no stage a derived body calls, a query builder of another module where a
  value goes, a query starting from an entity type, a condition anywhere but the body and `if`, a
  comparison of something that is no field, and a name no argument binds, located at the head.
  """
  @spec function(Macro.t(), Macro.t(), Macro.Env.t()) :: {list(atom), Macro.t(), boolean}
  def function(name, {:fn, meta, [{:->, arrow_meta, [args, body]}]}, env) do
    names = Enum.map(args, fn {arg_name, _meta, _context} -> arg_name end)

    state = %{
      env: env,
      field: "derived field #{Macro.to_string(name)} in #{inspect(env.module)}",
      head_line: arrow_meta[:line] || meta[:line] || env.line,
      names: names
    }

    lowered_body = body(body, state)

    {names, lowered_body, builder_call?(lowered_body)}
  end

  @doc """
  Returns the stages a derived body may call, as the keyword list `import/2`'s `:only` takes.
  """
  @spec stages() :: keyword(pos_integer)
  def stages, do: @stages

  @doc """
  Validates that every call the given module's derived bodies make to the module's own functions
  calls one it defines, and stands where a query goes. Run once the module body is evaluated, since
  the functions are usually defined below the fields that call them.

  Returns :ok, or raises Hologram.CompileError located at the call: a function the module neither
  defines nor imports is Elixir the body can't compute, and one standing where a value goes is a
  query builder in the wrong place.
  """
  @spec validate_own_builders!(module) :: :ok
  def validate_own_builders!(module) do
    locations =
      module
      |> Module.get_attribute(:__derived_locations__)
      |> Map.new()

    module
    |> Module.get_attribute(:__derived_bodies__)
    |> Enum.reverse()
    |> Enum.each(fn {name, _args, body} ->
      {file, line} = Map.fetch!(locations, name)

      state = %{
        env: %{file: file, line: line},
        field: "derived field #{inspect(name)} in #{inspect(module)}"
      }

      Macro.prewalk(body, &validate_own_builder!(&1, module, state))
    end)
  end

  # The whole body: a condition, which makes a boolean field, or anything an Elixir position takes.
  defp body(ast, state) do
    if condition?(ast) do
      condition_call(ast, state)
    else
      elixir_position(ast, :query, state)
    end
  end

  # Whether the given lowered body calls a query builder - the build resolves such a body by
  # following the builder, so it is told which fields need that. The lowering names a builder of
  # another module by the module itself, an imported one included, where the calls it writes itself
  # name Hologram.Entity.Derived by its alias, and it marks a call to the module's own function.
  defp builder_call?(lowered_body) do
    {_body, found?} =
      Macro.prewalk(lowered_body, false, fn
        {{:., _dot_meta, [module, _function]}, _meta, args} = ast, _found?
        when is_atom(module) and is_list(args) ->
          {ast, true}

        {_name, meta, args} = ast, found? when is_list(meta) and is_list(args) ->
          {ast, found? or Keyword.has_key?(meta, @own_builder_key)}

        ast, found? ->
          {ast, found?}
      end)

    found?
  end

  # The module a query builder call goes to - refused when the call computes in Elixir instead: a
  # call into Elixir's or Erlang's own modules, or on what is no module - or names a query stage
  # through its module.
  defp builder_module!({{:., _dot_meta, [target, function]}, _meta, args} = ast, state) do
    module = remote_module(target, state)
    spelled = "#{Macro.to_string(target)}.#{function}/#{length(args)}"

    if module == nil or own_module?(module) do
      vocabulary_error!("calls #{spelled}", ast, state)
    end

    if module == Hologram.Query do
      compile_error!(
        "#{state.field} calls #{spelled} - a derived field calls the query stages unqualified: #{function}(...)",
        ast,
        state
      )
    end

    module
  end

  @spec compile_error!(String.t(), Macro.t(), map) :: no_return
  defp compile_error!(message, ast, state) do
    raise Hologram.CompileError, message: message, file: state.env.file, line: line(ast, state)
  end

  defp concat_operands({:<>, _meta, [left, right]}),
    do: concat_operands(left) ++ concat_operands(right)

  defp concat_operands(ast), do: [ast]

  defp condition?({operator, _meta, [_left, _right]})
       when operator in @comparison_operators or operator in [:and, :in, :or],
       do: true

  defp condition?({:not, _meta, [{:in, _in_meta, [_left, _right]}]}), do: true

  defp condition?(_ast), do: false

  defp condition_call(ast, state) do
    predicates = predicates(ast, state)

    quote do
      Derived.condition(unquote(state.env.module), unquote(predicates))
    end
  end

  # The name a comparison reads on its left: an argument, or a dot chain on one - the row's own
  # names, so the condition reads as a filter over the row. A refusal is located at the comparison,
  # since a value carries no line of its own.
  defp condition_name!(ast, comparison, state) do
    path = field_path(ast, state)

    cond do
      path != nil ->
        name_of(path)

      literal?(ast) or module_attribute?(ast) ->
        compile_error!(
          "#{state.field} compares #{Macro.to_string(ast)} on the left - a comparison reads a field on its left and what it is compared with on its right",
          comparison,
          state
        )

      true ->
        compile_error!(
          "#{state.field} compares #{Macro.to_string(ast)} - compare a derived field instead: declare #{Macro.to_string(ast)} as one and read it here",
          comparison,
          state
        )
    end
  end

  # What a comparison reads on its right: a value, an @attribute or another field of the row.
  defp condition_operand!(ast, comparison, state) do
    cond do
      module_attribute?(ast) ->
        module_attribute_value(ast)

      literal?(ast) ->
        ast

      path = field_path(ast, state) ->
        {:attribute, name_of(path)}

      remote_call?(ast) ->
        scalar_builder_error!(ast, state)

      local_call?(ast) ->
        local_call(ast, :scalar, state)

      true ->
        compile_error!(
          "#{state.field} compares with #{Macro.to_string(ast)} - the other side of a comparison is a value, an @attribute or a field",
          comparison,
          state
        )
    end
  end

  defp described_use({name, _meta, args}) when is_atom(name) and is_list(args) do
    case Atom.to_string(name) do
      "sigil_" <> letter -> "uses the sigil ~#{letter}"
      _spelled when name in @special_forms -> "uses #{name}"
      spelled -> "calls #{spelled}/#{length(args)}"
    end
  end

  defp described_use(ast), do: "holds #{Macro.to_string(ast)}"

  defp elixir_position({:|>, _meta, [left, right]}, where, state) do
    left
    |> Macro.pipe(right, 0)
    |> elixir_position(where, state)
  end

  defp elixir_position({:@, _meta, [{_name, _name_meta, context}]} = ast, _where, _state)
       when is_atom(context) do
    module_attribute_value(ast)
  end

  defp elixir_position({:__aliases__, _meta, _segments} = ast, _where, state) do
    compile_error!(
      "#{state.field} reads #{Macro.to_string(ast)} - a derived field's query starts from a relationship of the row, so write it through an argument",
      ast,
      state
    )
  end

  defp elixir_position({name, _meta, context}, _where, state)
       when is_atom(name) and is_atom(context) do
    if name in state.names do
      field_call([name], state)
    else
      unbound_error!(name, state)
    end
  end

  defp elixir_position({{:., _dot_meta, [_left, _field]}, _meta, []} = ast, where, state) do
    case Expression.hops(ast) do
      [root | _rest] = path when is_atom(root) ->
        if root in state.names, do: field_call(path, state), else: unbound_error!(root, state)

      nil ->
        remote_call(ast, where, state)
    end
  end

  defp elixir_position({{:., _dot_meta, [_module, _function]}, _meta, args} = ast, where, state)
       when is_list(args) do
    remote_call(ast, where, state)
  end

  defp elixir_position({:<>, _meta, [_left, _right]} = ast, _where, state) do
    operands =
      ast
      |> concat_operands()
      |> Enum.map(&elixir_position(&1, :scalar, state))

    quote do
      Derived.concat(unquote(operands))
    end
  end

  defp elixir_position({:if, _meta, [condition, clauses]} = ast, _where, state)
       when is_list(clauses) do
    if not condition?(condition) do
      compile_error!(
        "#{state.field} branches on #{Macro.to_string(condition)} - the condition of if compares fields with ==, !=, <, <=, >, >=, in and not in, joined by and and or",
        ast,
        state
      )
    end

    if not Keyword.keyword?(clauses) or Keyword.keys(clauses) -- [:do, :else] != [] or
         not Keyword.has_key?(clauses, :do) do
      vocabulary_error!("uses if with #{Macro.to_string(clauses)}", ast, state)
    end

    then_branch = elixir_position(Keyword.fetch!(clauses, :do), :scalar, state)
    else_branch = elixir_position(Keyword.get(clauses, :else), :scalar, state)
    condition = condition_call(condition, state)

    quote do
      Derived.if_value(unquote(condition), unquote(then_branch), unquote(else_branch))
    end
  end

  defp elixir_position({:=, _meta, [left, _right]} = ast, _where, state) do
    compile_error!(
      "#{state.field} binds #{Macro.to_string(left)} - a derived field's body is one expression, with nothing bound along the way",
      ast,
      state
    )
  end

  defp elixir_position({:__block__, _meta, expressions}, where, state)
       when is_list(expressions) do
    case Enum.find(expressions, &match?({:=, _meta, [_left, _right]}, &1)) do
      nil when length(expressions) == 1 ->
        elixir_position(hd(expressions), where, state)

      nil ->
        compile_error!(
          "#{state.field} has a body of #{length(expressions)} expressions - a derived field's body is one expression",
          hd(expressions),
          state
        )

      binding ->
        elixir_position(binding, where, state)
    end
  end

  defp elixir_position({operator, _meta, [_left, _right]} = ast, _where, state)
       when operator in @comparison_operators or operator in [:and, :in, :or] do
    misplaced_condition_error!(ast, state)
  end

  defp elixir_position({:not, _meta, [{:in, _in_meta, [_left, _right]}]} = ast, _where, state) do
    misplaced_condition_error!(ast, state)
  end

  defp elixir_position({sign, _meta, [number]} = ast, _where, _state)
       when sign in [:+, :-] and is_number(number),
       do: ast

  defp elixir_position({stage, meta, [source | rest] = args} = ast, where, state)
       when is_atom(stage) and is_list(args) do
    if {stage, length(args)} in @stages do
      {stage, meta,
       [elixir_position(source, :query, state) | Enum.map(rest, &query_position(&1, state))]}
    else
      local_call(ast, where, state)
    end
  end

  defp elixir_position({name, _meta, []} = ast, where, state) when is_atom(name) do
    local_call(ast, where, state)
  end

  defp elixir_position(ast, _where, _state)
       when is_atom(ast) or is_number(ast) or is_binary(ast),
       do: ast

  defp elixir_position(ast, _where, state) when is_list(ast) do
    compile_error!(
      "#{state.field} holds the list #{Macro.to_string(ast)} - a list of values stands only on the right side of in",
      ast,
      state
    )
  end

  defp elixir_position(ast, _where, state) do
    vocabulary_error!(described_use(ast), ast, state)
  end

  defp field_call(path, state) do
    quote do
      Derived.field(unquote(state.env.module), unquote(path))
    end
  end

  # The path of fields an argument or a dot chain on one reads - nil for anything else.
  defp field_path({name, _meta, context}, state) when is_atom(name) and is_atom(context) do
    if name in state.names, do: [name], else: unbound_error!(name, state)
  end

  defp field_path({{:., _dot_meta, [_left, _field]}, _meta, []} = ast, state) do
    case Expression.hops(ast) do
      [root | _rest] = path when is_atom(root) ->
        if root in state.names, do: path, else: unbound_error!(root, state)

      nil ->
        nil
    end
  end

  defp field_path(_ast, _state), do: nil

  # Resolved through expand_import/5 rather than looked up, since the call is written out as a
  # remote one: the expansion is what tells the compiler the import is used, so it doesn't warn
  # that it is unused.
  defp imported_module(name, meta, arity, state) do
    case Macro.Env.expand_import(state.env, meta, name, arity, allow_locals: false) do
      {:function, module, _name} -> module
      {:macro, module, _expander} -> module
      {:error, _reason} -> nil
    end
  end

  # The node's line, or the declaration's for a node that carries none - a literal list or tuple.
  defp line({_head, meta, _args}, state) when is_list(meta), do: meta[:line] || state.env.line

  defp line(_ast, state), do: state.env.line

  # A value written out: an atom, a string or a number, a signed one included - -1 is a call to -
  # in the AST.
  defp literal?({sign, _meta, [number]}) when sign in [:+, :-], do: is_number(number)

  defp literal?(ast), do: is_atom(ast) or is_number(ast) or is_binary(ast)

  # A local call that is no query stage calls a function the module imports or its own. An import
  # from another module of the project is a query builder like any call into it, one from Elixir or
  # Erlang computes in Elixir, and a stage the module imports from Hologram.Query but a derived body
  # can't call stays refused. A call to the module's own function is a query builder too, marked for
  # validate_own_builders!/1, which knows once the module body has run whether the module defines it.
  defp local_call({name, meta, args} = ast, where, state) do
    arity = length(args)

    cond do
      name in @special_forms or sigil?(name) or Macro.operator?(name, arity) ->
        vocabulary_error!(described_use(ast), ast, state)

      module = imported_module(name, meta, arity, state) ->
        if module == Hologram.Query or own_module?(module) do
          vocabulary_error!(described_use(ast), ast, state)
        end

        elixir_position({{:., meta, [module, name]}, meta, args}, where, state)

      true ->
        {name, Keyword.put(meta, @own_builder_key, where),
         Enum.map(args, &elixir_position(&1, :query, state))}
    end
  end

  # A call written without a module that local_call/3 judges: what the AST spells as a call but is
  # a stage, an operator, a special form, a sigil or an alias is judged where it is met.
  defp local_call?({name, _meta, args}) when is_atom(name) and is_list(args) do
    arity = length(args)

    name not in [:__aliases__ | @special_forms] and {name, arity} not in @stages and
      not sigil?(name) and not Macro.operator?(name, arity)
  end

  defp local_call?(_ast), do: false

  # The right side of in: a list of values and @attributes, or an @attribute holding the list.
  defp membership!(ast, comparison, state) when is_list(ast) do
    Enum.map(ast, fn element ->
      cond do
        module_attribute?(element) -> module_attribute_value(element)
        literal?(element) -> element
        true -> membership_error!(ast, comparison, state)
      end
    end)
  end

  defp membership!(ast, comparison, state) do
    if module_attribute?(ast),
      do: module_attribute_value(ast),
      else: membership_error!(ast, comparison, state)
  end

  @spec membership_error!(Macro.t(), Macro.t(), map) :: no_return
  defp membership_error!(ast, comparison, state) do
    compile_error!(
      "#{state.field} looks a field up in #{Macro.to_string(ast)} - the right side of in is a list of values or an @attribute",
      comparison,
      state
    )
  end

  @spec misplaced_condition_error!(Macro.t(), map) :: no_return
  defp misplaced_condition_error!(ast, state) do
    compile_error!(
      "#{state.field} holds the condition #{Macro.to_string(ast)} where a value goes - a condition stands as the whole body or as the condition of if",
      ast,
      state
    )
  end

  defp module_attribute?({:@, _meta, [{_name, _name_meta, context}]}) when is_atom(context),
    do: true

  defp module_attribute?(_ast), do: false

  # A module attribute is read where the declaration is evaluated, as a function body reads one where
  # the function is defined - the module body is expanded whole before any of it runs, so the value
  # is not there yet when this does. The fragment is unquoted when the body is escaped into the
  # declaration, so the read lands in the module body, and the value it reads into the body.
  defp module_attribute_value(ast) do
    value_ast =
      quote do
        Macro.escape(unquote(ast))
      end

    {:unquote, [], [value_ast]}
  end

  defp name_of([name]), do: name

  defp name_of(path), do: path

  defp or_alternatives({:or, _meta, [left, right]}),
    do: or_alternatives(left) ++ or_alternatives(right)

  defp or_alternatives(ast), do: [ast]

  defp own_module?(module) do
    erlang_module? =
      module
      |> Atom.to_string()
      |> String.starts_with?("Elixir.")
      |> Kernel.not()

    elixir_app? =
      Code.ensure_loaded?(module) and
        match?({:ok, app} when app in @elixir_apps, :application.get_application(module))

    erlang_module? or elixir_app?
  end

  # A pinned value of a query is known when the definition is built: an argument, a chain on one, an
  # @attribute or a literal.
  defp pinned!(ast, state) do
    cond do
      module_attribute?(ast) ->
        module_attribute_value(ast)

      literal?(ast) or Macro.quoted_literal?(ast) ->
        ast

      path = field_path(ast, state) ->
        field_call(path, state)

      true ->
        compile_error!(
          "#{state.field} pins #{Macro.to_string(ast)} - a pinned value in a derived field's query is an argument, a chain on one, an @attribute or a literal",
          ast,
          state
        )
    end
  end

  # A condition in the filter data form, its names the row's: comparisons and memberships joined by
  # and into a list, by or into a disjunction of lists.
  defp predicates({:and, _meta, [left, right]}, state),
    do: predicates(left, state) ++ predicates(right, state)

  defp predicates({:or, _meta, [_left, _right]} = ast, state) do
    alternatives =
      ast
      |> or_alternatives()
      |> Enum.map(&predicates(&1, state))

    [{:or, alternatives}]
  end

  defp predicates({:not, _meta, [{:in, _in_meta, [left, right]}]} = ast, state),
    do: [{condition_name!(left, ast, state), {:not_in, membership!(right, ast, state)}}]

  defp predicates({:in, _meta, [left, right]} = ast, state),
    do: [{condition_name!(left, ast, state), {:in, membership!(right, ast, state)}}]

  defp predicates({operator, _meta, [left, right]} = ast, state)
       when operator in @comparison_operators do
    [{condition_name!(left, ast, state), {operator, condition_operand!(right, ast, state)}}]
  end

  defp predicates(ast, state) do
    compile_error!(
      "#{state.field} joins #{Macro.to_string(ast)} into a condition - a condition compares fields with ==, !=, <, <=, >, >=, in and not in, joined by and and or",
      ast,
      state
    )
  end

  defp query_position({:^, meta, [expr]}, state), do: {:^, meta, [pinned!(expr, state)]}

  defp query_position({:__aliases__, _meta, _segments} = ast, state) do
    Macro.expand(ast, state.env)
  end

  defp query_position({head, meta, args}, state) when is_list(args) do
    {query_position(head, state), meta, Enum.map(args, &query_position(&1, state))}
  end

  defp query_position({left, right}, state) do
    {query_position(left, state), query_position(right, state)}
  end

  defp query_position(list, state) when is_list(list),
    do: Enum.map(list, &query_position(&1, state))

  defp query_position(ast, _state), do: ast

  # A call into another module is a query builder, standing where a query goes, its arguments read
  # as the body is.
  defp remote_call(ast, :scalar, state), do: scalar_builder_error!(ast, state)

  defp remote_call({{:., dot_meta, [_target, function]}, meta, args} = ast, :query, state) do
    module = builder_module!(ast, state)

    {{:., dot_meta, [module, function]}, meta,
     Enum.map(args, &elixir_position(&1, :query, state))}
  end

  defp remote_call?({{:., _dot_meta, [_module, _function]}, _meta, args}) when is_list(args),
    do: true

  defp remote_call?(_ast), do: false

  defp remote_module({:__aliases__, _meta, _segments} = ast, state),
    do: Macro.expand(ast, state.env)

  defp remote_module(module, _state) when is_atom(module), do: module

  defp remote_module(_target, _state), do: nil

  @spec scalar_builder_error!(Macro.t(), map) :: no_return
  defp scalar_builder_error!(
         {{:., _dot_meta, [target, function]}, _meta, args} = ast,
         state
       ) do
    builder_module!(ast, state)

    compile_error!(
      "#{state.field} calls #{Macro.to_string(target)}.#{function}/#{length(args)} where a value goes - a call to another module builds a query, so it stands where a query goes",
      ast,
      state
    )
  end

  defp sigil?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("sigil_")
  end

  # A name no argument binds is a field the head forgot, so the refusal is located at the head.
  @spec unbound_error!(atom, map) :: no_return
  defp unbound_error!(name, state) do
    raise Hologram.CompileError,
      message:
        "#{name} is not an argument of the function of #{state.field} - add it to the head to read the field",
      file: state.env.file,
      line: state.head_line
  end

  # Returns the node as given, as Macro.prewalk/2 takes it.
  defp validate_own_builder!({name, meta, args} = ast, module, state)
       when is_list(meta) and is_list(args) do
    arity = length(args)

    case Keyword.fetch(meta, @own_builder_key) do
      {:ok, where} ->
        cond do
          not Module.defines?(module, {name, arity}) ->
            vocabulary_error!("calls #{name}/#{arity}", ast, state)

          where == :scalar ->
            compile_error!(
              "#{state.field} calls #{name}/#{arity} where a value goes - a call to a query builder builds a query, so it stands where a query goes",
              ast,
              state
            )

          true ->
            ast
        end

      :error ->
        ast
    end
  end

  defp validate_own_builder!(ast, _module, _state), do: ast

  @spec vocabulary_error!(String.t(), Macro.t(), map) :: no_return
  defp vocabulary_error!(what, ast, state) do
    compile_error!("#{state.field} #{what} - #{@vocabulary_reason}", ast, state)
  end
end
