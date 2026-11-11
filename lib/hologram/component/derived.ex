defmodule Hologram.Component.Derived do
  @moduledoc false

  # The derived fields of a component or a page: declared by derived/3, checked once the module body
  # has run, and reflected as __derived__/0 with a public function per field holding its body.
  #
  # A field's function is hoisted into a def of the module rather than kept as a closure, so its body
  # is ordinary module code: called on the server, walked by the build through IR, and transpiled for
  # the client, which the call graph reaches through the capture __derived__/0 holds.

  alias Hologram.Compiler.AST
  alias Hologram.Entity.Validator, as: EntityValidator

  # The query macros whose arguments after the source are query vocabulary, where a bare name is the
  # queried row's and only a pinned expression reads the surrounding Elixir.
  @query_macros [filter: 2, include: 2, paginate: 2, skip: 2, sort: 2, take: 2]

  @doc """
  Returns the AST of code that accumulates the given derived field declaration in __derived__
  module attribute, after checking the shape of its function at the declaration's line: a capture of
  a zero-arity function stands for the function calling it, and the function has one clause, no
  guard and arguments that are distinct bare names.
  """
  @spec declaration(any, Macro.t(), Macro.t(), Macro.Env.t()) :: AST.t()
  def declaration(name, type, definition, env) do
    if not is_atom(name) do
      raise Hologram.CompileError,
        message:
          "the name of derived field #{Macro.to_string(name)} in #{inspect(env.module)} must be an atom",
        file: env.file,
        line: env.line
    end

    definition = Hologram.Derived.function(name, definition, env)

    EntityValidator.validate_derived_function!(name, definition, env)

    {:fn, _meta, [{:->, _arrow_meta, [args, body]}]} = definition
    arg_names = Enum.map(args, fn {arg_name, _meta, _context} -> arg_name end)

    declaration = {name, args, arg_names, resolve_at_line(body, env), env.line}

    quote do
      Module.put_attribute(
        __MODULE__,
        :__derived__,
        {unquote(Macro.escape(declaration, unquote: true)), unquote(type)}
      )
    end
  end

  @doc """
  Returns the AST of the given component or page module's derived field reflection: a public
  function per field holding its body, named `__derived_<name>__`, and `__derived__/0` listing the
  fields in the order they can be computed - each after every field it reads, the declaration order
  deciding the rest. Each entry names the field, its type, the names its function's arguments bind,
  a capture of that function and whether the field reads state, directly or through another field.

  Raises Hologram.CompileError, located at the declaration, when a field's name is taken by a prop
  (a param on a page), a state entry, the cid or another derived field, when its function's head
  names what is none of the module's props (params), state entries and other derived fields, or the
  field itself, when its body reads a field its head doesn't name, and when fields read each other
  in a cycle.
  """
  @spec reflection(Macro.Env.t()) :: AST.t()
  def reflection(env) do
    module = env.module

    declarations =
      module
      |> Module.get_attribute(:__derived__)
      |> Enum.reverse()

    {holder, inputs} = inputs(module)

    validate_names!(declarations, inputs, env)

    fields = Map.merge(inputs, Map.new(declarations, &{declaration_name(&1), "derived field"}))

    Enum.each(declarations, &validate_head!(&1, fields, holder, env))
    Enum.each(declarations, &validate_body!(&1, fields, env))

    ordered = order!(declarations, env)
    reads_state = reads_state(ordered, inputs)

    entries =
      Enum.map(ordered, fn {{name, _args, arg_names, _body, _line}, type} ->
        function_name = function_name(name)
        arity = length(arg_names)

        quote do
          %{
            args: unquote(arg_names),
            function: &(__MODULE__.unquote(function_name) / unquote(arity)),
            name: unquote(name),
            reads_state: unquote(MapSet.member?(reads_state, name)),
            type: unquote(Macro.escape(type))
          }
        end
      end)

    functions =
      Enum.map(declarations, fn {{name, args, _arg_names, body, _line}, _type} ->
        quote do
          @doc false
          def unquote(function_name(name))(unquote_splicing(args)) do
            unquote(body)
          end
        end
      end)

    reflection_function =
      quote do
        @doc """
        Returns the list of derived field definitions for the compiled component or page, in the
        order they can be computed.
        """
        @spec __derived__() :: list(map)
        def __derived__, do: unquote(entries)
      end

    [reflection_function | functions]
  end

  @doc """
  Returns the AST of code that registers __derived__ module attribute.
  """
  @spec register_accumulator() :: AST.t()
  def register_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__derived__, accumulate: true)
    end
  end

  defp compile_error!(message, env, line) do
    raise Hologram.CompileError, message: message, file: env.file, line: line
  end

  defp declaration_name({{name, _args, _arg_names, _body, _line}, _type}), do: name

  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp function_name(name), do: :"__derived_#{name}__"

  # The names a derived field's function can read besides other derived fields, each with how the
  # messages describe what holds it. A page's params stand where a component's props do.
  defp inputs(module) do
    {holders, holder} =
      if Module.defines?(module, {:__is_hologram_page__, 0}) do
        {Module.get_attribute(module, :__params__), "param"}
      else
        {Module.get_attribute(module, :__props__), "prop"}
      end

    state = Module.get_attribute(module, :__state__)

    inputs =
      holders
      |> Enum.map(fn {name, _type, _opts} -> {name, holder} end)
      |> Enum.concat(Enum.map(state, fn {name, _type, _opts} -> {name, "state entry"} end))
      |> Map.new()

    {holder, inputs}
  end

  defp module_label(env), do: inspect(env.module)

  # A field comes after every field it reads, and of the fields free to come next the one declared
  # first does. Whatever is left once none is free reads a cycle or depends on one, so the cycle
  # reported is a strongly connected part of what is left - its fields in declaration order, at
  # the first one's line.
  defp order!(declarations, env) do
    names = Enum.map(declarations, &declaration_name/1)

    reads =
      Map.new(declarations, fn {{name, _args, arg_names, _body, _line}, _type} ->
        {name, Enum.filter(arg_names, &(&1 in names))}
      end)

    case order_step(declarations, reads, []) do
      {ordered, []} -> ordered
      {_ordered, left} -> raise_cycle!(left, reads, env)
    end
  end

  defp order_step([], _reads, ordered), do: {Enum.reverse(ordered), []}

  defp order_step(left, reads, ordered) do
    done = Enum.map(ordered, &declaration_name/1)

    case Enum.find(left, fn declaration ->
           reads
           |> Map.fetch!(declaration_name(declaration))
           |> Enum.all?(&(&1 in done))
         end) do
      nil -> {Enum.reverse(ordered), left}
      free -> order_step(List.delete(left, free), reads, [free | ordered])
    end
  end

  # Whether the given call is one of the query macros, given the number of arguments a pipe leaves
  # out of it: called unqualified where Hologram.Query is imported, by the module or earlier in the
  # body, or through the module, an alias of it included.
  defp query_macro?({{:., _dot_meta, [module_ast, name]}, _meta, args}, piped, state)
       when is_list(args) do
    {name, length(args) + piped} in @query_macros and query_module?(module_ast, state)
  end

  defp query_macro?({name, _meta, args}, piped, state) when is_atom(name) and is_list(args) do
    arity = length(args) + piped

    {name, arity} in @query_macros and
      ({name, arity} in state.query_imports or
         match?(
           [{_kind, Hologram.Query} | _rest],
           Macro.Env.lookup_import(state.env, {name, arity})
         ))
  end

  defp query_macro?(_ast, _piped, _state), do: false

  defp query_module?({:__aliases__, _meta, [alias_name]}, state) when is_atom(alias_name) do
    alias_name in state.query_aliases or
      Macro.expand({:__aliases__, [], [alias_name]}, state.env) == Hologram.Query
  end

  defp query_module?(module_ast, state), do: Macro.expand(module_ast, state.env) == Hologram.Query

  @spec raise_cycle!(list, %{atom => [atom]}, Macro.Env.t()) :: no_return
  defp raise_cycle!(left, reads, env) do
    graph = :digraph.new()

    try do
      Enum.each(left, &:digraph.add_vertex(graph, declaration_name(&1)))

      Enum.each(left, fn declaration ->
        name = declaration_name(declaration)

        reads
        |> Map.fetch!(name)
        |> Enum.each(&:digraph.add_edge(graph, name, &1))
      end)

      cycles =
        graph
        |> :digraph_utils.strong_components()
        |> Enum.filter(&(length(&1) > 1))

      members =
        Enum.find_value(left, fn declaration ->
          Enum.find(cycles, &(declaration_name(declaration) in &1))
        end)

      [{{_name, _args, _arg_names, _body, line}, _type} | _rest] =
        cycle = Enum.filter(left, &(declaration_name(&1) in members))

      spelled = Enum.map_join(cycle, ", ", &inspect(declaration_name(&1)))

      compile_error!(
        "derived fields in #{module_label(env)} read each other in a cycle: #{spelled}",
        env,
        line
      )
    after
      :digraph.delete(graph)
    end
  end

  # The fields whose function reads a state entry, directly or through a field that does - in the
  # order given, every field a field reads comes before it.
  defp reads_state(ordered, inputs) do
    Enum.reduce(ordered, MapSet.new(), fn {{name, _args, arg_names, _body, _line}, _type}, acc ->
      if Enum.any?(arg_names, &(Map.get(inputs, &1) == "state entry" or &1 in acc)) do
        MapSet.put(acc, name)
      else
        acc
      end
    end)
  end

  # The body is compiled into its def once the module body has run, so what a def at the declaration
  # would read there is read there: a module attribute's value, through an unquote fragment the
  # declaration's escape evaluates where it stands, and an alias the module has declared. An alias
  # the body declares itself is known only inside the body, and is left as written.
  defp resolve_at_line(body, env) do
    Macro.prewalk(body, fn
      {:@, _meta, [{attribute, _attribute_meta, context}]}
      when is_atom(attribute) and is_atom(context) ->
        {:unquote, [],
         [
           quote do
             Macro.escape(Module.get_attribute(__MODULE__, unquote(attribute)))
           end
         ]}

      {:__aliases__, meta, [first | _rest] = segments} = ast when is_atom(first) ->
        case Macro.Env.expand_alias(env, meta, segments, trace: false) do
          {:alias, module} -> module
          :error -> ast
        end

      ast ->
        ast
    end)
  end

  # The body names only what its head binds of the module's fields, whether it reads one or binds a
  # local under one's name. Inside a query macro's arguments after the source a bare name is the
  # queried row's, so only what is pinned there is read.
  defp unknown_input_message(arg_name, name, fields, holder, env) do
    readable =
      fields
      |> Map.keys()
      |> List.delete(name)
      |> Enum.sort()
      |> Enum.join(", ")

    listed =
      if readable == "",
        do: ", and #{module_label(env)} declares none",
        else: ": #{readable}"

    "#{arg_name} is not a #{holder}, state entry or derived field of #{module_label(env)} - the arguments of derived field #{inspect(name)}'s function name the fields it reads#{listed}"
  end

  defp validate_body!({{name, _args, arg_names, body, line}, _type}, fields, env) do
    state = %{
      arg_names: arg_names,
      env: env,
      fields: fields,
      line: line,
      name: name,
      pattern?: false,
      query_aliases: [],
      query_imports: []
    }

    walk_body(body, state)

    :ok
  end

  defp validate_field_name!(var_name, %{name: var_name, pattern?: false} = state) do
    compile_error!(
      "derived field #{inspect(var_name)} in #{module_label(state.env)} reads itself - a derived field is computed from other fields",
      state.env,
      state.line
    )
  end

  defp validate_field_name!(var_name, %{name: var_name, pattern?: true} = state) do
    compile_error!(
      "#{var_name} is the name of derived field #{inspect(var_name)} in #{module_label(state.env)}, so its function can't bind a local of that name - give the local another name",
      state.env,
      state.line
    )
  end

  defp validate_field_name!(var_name, state) do
    with {:ok, holder} <- Map.fetch(state.fields, var_name),
         false <- var_name in state.arg_names do
      message =
        if state.pattern? do
          "#{var_name} is a #{holder} of #{module_label(state.env)}, so derived field #{inspect(state.name)}'s function can't bind a local of that name - give the local another name"
        else
          "#{var_name} is a #{holder} of #{module_label(state.env)}, which derived field #{inspect(state.name)}'s function doesn't name - add it to the head to read it"
        end

      compile_error!(message, state.env, state.line)
    end

    :ok
  end

  defp validate_head!({{name, _args, arg_names, _body, line}, _type}, fields, holder, env) do
    Enum.each(arg_names, fn arg_name ->
      cond do
        arg_name == name ->
          compile_error!(
            "derived field #{inspect(name)} in #{module_label(env)} reads itself - a derived field is computed from other fields",
            env,
            line
          )

        not Map.has_key?(fields, arg_name) ->
          compile_error!(unknown_input_message(arg_name, name, fields, holder, env), env, line)

        true ->
          :ok
      end
    end)
  end

  defp validate_names!(declarations, inputs, env) do
    cid_holder =
      if Module.defines?(env.module, {:__is_hologram_page__, 0}),
        do: "the layout's cid prop",
        else: "the cid prop"

    Enum.reduce(declarations, MapSet.new(), fn {{name, _args, _arg_names, _body, line}, _type},
                                               declared ->
      holder =
        cond do
          name == :cid -> cid_holder
          MapSet.member?(declared, name) -> "another derived field"
          holder = Map.get(inputs, name) -> with_article(holder)
          true -> nil
        end

      if holder do
        compile_error!(
          "derived field #{inspect(name)} in #{module_label(env)} has the same name as #{holder}, which it would shadow - give them different names",
          env,
          line
        )
      end

      MapSet.put(declared, name)
    end)
  end

  # Each walk returns the state the rest of a block is walked with, which is what carries an import
  # or alias of Hologram.Query to the expressions after it.
  defp walk_body({:@, _meta, [_attribute]}, state), do: state

  # A capture names a function, not a variable.
  defp walk_body({:&, _meta, [{:/, _slash_meta, [{name, _name_meta, context}, arity]}]}, state)
       when is_atom(name) and is_atom(context) and is_integer(arity),
       do: state

  defp walk_body({:__block__, _meta, expressions}, state) when is_list(expressions) do
    Enum.reduce(expressions, state, &walk_body/2)
  end

  defp walk_body({:import, _meta, [module_ast | opts]}, state) do
    if query_module?(module_ast, state) do
      imported =
        case opts do
          [[only: only]] when is_list(only) -> Enum.filter(@query_macros, &(&1 in only))
          _all -> @query_macros
        end

      %{state | query_imports: imported ++ state.query_imports}
    else
      state
    end
  end

  defp walk_body({directive, _meta, [module_ast | opts]}, state)
       when directive in [:alias, :require] do
    if query_module?(module_ast, state) do
      case {directive, opts} do
        {_directive, [[as: {:__aliases__, _as_meta, [as_name]}]]} ->
          %{state | query_aliases: [as_name | state.query_aliases]}

        {:alias, _opts} ->
          %{state | query_aliases: [:Query | state.query_aliases]}

        {:require, _opts} ->
          state
      end
    else
      state
    end
  end

  defp walk_body({:=, _meta, [left, right]}, state) do
    walk_body(right, state)
    walk_pattern(left, state)

    state
  end

  defp walk_body({:->, _meta, [[{:when, _when_meta, patterns_and_guard}], body]}, state) do
    {patterns, [guard]} = Enum.split(patterns_and_guard, -1)

    Enum.each(patterns, &walk_pattern(&1, state))
    walk_body(guard, state)
    walk_body(body, state)

    state
  end

  defp walk_body({:->, _meta, [patterns, body]}, state) when is_list(patterns) do
    Enum.each(patterns, &walk_pattern(&1, state))
    walk_body(body, state)

    state
  end

  defp walk_body({:<-, _meta, [left, right]}, state) do
    walk_body(right, state)
    walk_pattern(left, state)

    state
  end

  defp walk_body({:<<>>, _meta, segments}, state) when is_list(segments) do
    Enum.each(segments, &walk_segment(&1, state))

    state
  end

  defp walk_body({:^, _meta, [expr]}, state) do
    walk_body(expr, %{state | pattern?: false})

    state
  end

  defp walk_body({:|>, _meta, [left, right]}, state) do
    walk_body(left, state)

    if query_macro?(right, 1, state) do
      {_name, _meta, args} = right

      walk_pins(args, state)
    else
      walk_body(right, state)
    end

    state
  end

  defp walk_body({_call, _meta, [source | rest]} = ast, state) when is_list(rest) do
    if query_macro?(ast, 0, state) do
      walk_body(source, state)
      walk_pins(rest, state)
    else
      walk_children(ast, state)
    end

    state
  end

  defp walk_body({var_name, _meta, nil}, state) when is_atom(var_name) do
    validate_field_name!(var_name, state)

    state
  end

  defp walk_body(ast, state) do
    walk_children(ast, state)

    state
  end

  defp walk_children({head, _meta, args}, state) when is_list(args) do
    walk_body(head, state)
    Enum.each(args, &walk_body(&1, state))
  end

  defp walk_children({left, right}, state) do
    walk_body(left, state)
    walk_body(right, state)
  end

  defp walk_children(list, state) when is_list(list), do: Enum.each(list, &walk_body(&1, state))

  defp walk_children(_ast, _state), do: :ok

  defp walk_pattern(ast, state), do: walk_body(ast, %{state | pattern?: true})

  defp walk_pins({:^, _meta, [expr]}, state), do: walk_body(expr, %{state | pattern?: false})

  defp walk_pins({head, _meta, args}, state) when is_list(args) do
    walk_pins(head, state)
    Enum.each(args, &walk_pins(&1, state))
  end

  defp walk_pins({left, right}, state) do
    walk_pins(left, state)
    walk_pins(right, state)
  end

  defp walk_pins(list, state) when is_list(list), do: Enum.each(list, &walk_pins(&1, state))

  defp walk_pins(_ast, _state), do: :ok

  # A segment's type specifiers are no variables - only what size/1 and unit/1 take is read.
  defp walk_segment({:"::", _meta, [value, spec]}, state) do
    walk_body(value, state)
    walk_specifiers(spec, %{state | pattern?: false})
  end

  defp walk_segment(segment, state), do: walk_body(segment, state)

  defp walk_specifiers({:-, _meta, [left, right]}, state) do
    walk_specifiers(left, state)
    walk_specifiers(right, state)
  end

  defp walk_specifiers({:*, _meta, [left, right]}, state) do
    walk_specifiers(left, state)
    walk_specifiers(right, state)
  end

  defp walk_specifiers({specifier, _meta, [arg]}, state) when specifier in [:size, :unit],
    do: walk_body(arg, state)

  defp walk_specifiers(_spec, _state), do: :ok

  defp with_article("state entry"), do: "a state entry"

  defp with_article(holder), do: "a #{holder}"
end
