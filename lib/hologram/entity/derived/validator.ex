defmodule Hologram.Entity.Derived.Validator do
  @moduledoc false

  # The checks a derived field's definition passes once the build resolved it - the ones its
  # declaration alone can't answer, since they read the declarations of every type it reaches.

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Query
  alias Hologram.Reflection

  @quantifiers [:all, :any, :none]

  @doc """
  Validates the derived fields of the given entity types against their given resolved definitions,
  keyed by entity type and field name: the element type of a field holding rows is an entity type,
  every definition computes what its field declares, none reads a server-only attribute - a client
  computes derived fields over the rows it holds - and no derived fields read each other in a cycle.

  Returns :ok, or raises Hologram.CompileError listing every violation, each at the declaration of
  the field it is about.
  """
  @spec validate_model!(list(module), %{{module, atom} => Hologram.Entity.Derived.definition()}) ::
          :ok
  def validate_model!(entity_types, definitions) do
    fields =
      for entity_type <- Enum.sort(entity_types),
          {name, type, opts} <- entity_type.__derived__() do
        {entity_type, name, type, opts}
      end

    field_violations =
      Enum.flat_map(fields, fn {entity_type, name, type, opts} ->
        field_violations(
          entity_type,
          name,
          type,
          opts,
          Map.fetch!(definitions, {entity_type, name})
        )
      end)

    violations =
      field_violations
      |> Enum.concat(cycle_violations(fields, definitions))
      |> Enum.sort_by(fn {entity_type, name, _description} -> {entity_type, name} end)

    if violations != [] do
      descriptions =
        Enum.map_join(violations, "\n", fn {entity_type, name, description} ->
          "  * #{declaration_location(entity_type, name)}#{description}"
        end)

      raise Hologram.CompileError, message: "invalid data model:\n#{descriptions}"
    end

    :ok
  end

  defp clause_names(clauses, scope) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} ->
        Enum.flat_map(alternatives, &clause_names(&1, scope))

      {quantifier, {source, inner}} when quantifier in @quantifiers ->
        {source_type, hops} = source_start(source, scope)
        {set_hops, [set_name]} = Enum.split(hops, -1)
        set_owner_type = Entity.path_target(source_type, set_hops)
        related_type = set_type(set_owner_type, set_name)

        [{set_owner_type, set_name} | clause_names(inner, [related_type | scope])]

      {name, _operator, operand} ->
        names = [name | operand_names(operand)]

        names
        |> Enum.reject(&match?({:placeholder, _placeholder_name}, &1))
        |> Enum.map(&scoped_name(&1, scope))
    end)
  end

  # What a definition computes, as a refusal names it.
  defp computed({:value, value}), do: "the value #{inspect(value)}"

  defp computed({:concat, _operands}), do: "a string (<>)"

  defp computed({:condition, _clauses}), do: "a condition (:boolean)"

  defp computed({:query, %Query{cardinality: :count}}), do: "a count (:integer)"

  defp computed({:query, %Query{cardinality: :one, entity: entity_type}}),
    do: "one #{inspect(entity_type)} row"

  defp computed({:query, %Query{entity: entity_type}}),
    do: "a set of #{inspect(entity_type)} rows"

  # Whether a definition computes what the given declared type and options hold. A field holding a
  # value or one row may hold none, while a set holds rows - its typespec takes no nil - so a set's
  # definition computing nil is refused.
  defp computes?({[_target], _opts}, {:value, nil}), do: false

  defp computes?(_declared, {:value, nil}), do: true

  defp computes?(declared, {:value, value}), do: value_of_type?(value, declared)

  defp computes?({:string, _opts}, {:concat, _operands}), do: true

  defp computes?({:boolean, _opts}, {:condition, _clauses}), do: true

  defp computes?({type, _opts}, {:query, %Query{cardinality: :count}}),
    do: type in [:float, :integer]

  defp computes?({target, _opts}, {:query, %Query{cardinality: :one, entity: target}}), do: true

  defp computes?({[target], _opts}, {:query, %Query{cardinality: :set, entity: target}}),
    do: true

  defp computes?(_declared, _definition), do: false

  defp cycle_violation([{entity_type, name}]) do
    {entity_type, name,
     "derived field #{inspect(name)} in #{inspect(entity_type)} reads itself through a related row"}
  end

  defp cycle_violation(component) do
    [{first_type, first_name} | _later_fields] = fields = Enum.sort(component)
    spelled = Enum.map_join(fields, ", ", fn {type, name} -> "#{inspect(type)}.#{name}" end)

    {first_type, first_name, "derived fields read each other in a cycle: #{spelled}"}
  end

  # Edges from every derived field to the derived fields its definition reads, on any type - cycles
  # are the strongly connected components with more than one field, or a field reading itself through
  # a related row. Each is reported once, at its first field, naming every field on it.
  defp cycle_violations(fields, definitions) do
    graph = :digraph.new()

    try do
      Enum.each(fields, fn {entity_type, name, _type, _opts} ->
        :digraph.add_vertex(graph, {entity_type, name})
      end)

      Enum.each(fields, fn {entity_type, name, _type, _opts} ->
        entity_type
        |> read_names(Map.fetch!(definitions, {entity_type, name}))
        |> Enum.filter(fn {type, read_name} -> Derived.declared?(type, read_name) end)
        |> Enum.each(&:digraph.add_edge(graph, {entity_type, name}, &1))
      end)

      graph
      |> :digraph_utils.strong_components()
      |> Enum.filter(fn component ->
        match?([_first, _second | _rest], component) or
          {hd(component), hd(component)} in edges_of(graph, hd(component))
      end)
      |> Enum.map(&cycle_violation/1)
    after
      :digraph.delete(graph)
    end
  end

  defp declaration_location(entity_type, name) do
    case Map.fetch(entity_type.__derived_locations__(), name) do
      {:ok, {file, line}} -> "#{Path.relative_to_cwd(file)}:#{line}: "
      :error -> ""
    end
  end

  defp edges_of(graph, vertex) do
    graph
    |> :digraph.out_edges(vertex)
    |> Enum.map(fn edge ->
      {_edge, from, to, _label} = :digraph.edge(graph, edge)

      {from, to}
    end)
  end

  defp element_type_violations(entity_type, name, type) do
    element_type =
      case type do
        [target] -> target
        target when is_atom(target) -> if Reflection.alias?(target), do: target
      end

    if element_type != nil and not Reflection.entity?(element_type) do
      [
        {entity_type, name,
         "derived field #{inspect(name)} in #{inspect(entity_type)} is declared #{inspect(type)}, but #{inspect(element_type)} is not an entity type"}
      ]
    else
      []
    end
  end

  # The type of a name the row reads - an attribute, a system attribute, a reference field or a
  # derived field holding a value, of the row or of the related row a path leads to - with the
  # options an enum carries its values in.
  defp field_type(owner, name) do
    {subject_type, last_name} = resolved_name(owner, name)

    declarations =
      subject_type.__attributes__() ++
        subject_type.__system_attributes__() ++ subject_type.__derived__()

    case List.keyfind(declarations, last_name, 0) do
      {_name, type, opts} -> {type, opts}
      nil -> {:uuid, []}
    end
  end

  defp field_violations(entity_type, name, type, opts, definition) do
    declared = {type, opts}
    element_type_violations = element_type_violations(entity_type, name, type)

    type_violations =
      definition
      |> typed(entity_type)
      |> type_violations(declared, "its definition is")
      |> Enum.map(
        &{entity_type, name, "derived field #{inspect(name)} in #{inspect(entity_type)} #{&1}"}
      )

    server_only_violations =
      entity_type
      |> read_names(definition)
      |> Enum.filter(fn {type_read, read_name} -> server_only?(type_read, read_name) end)
      |> Enum.uniq()
      |> Enum.map(fn {type_read, read_name} ->
        {entity_type, name,
         "derived field #{inspect(name)} in #{inspect(entity_type)} reads #{inspect(type_read)}.#{read_name}, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value"}
      end)

    element_type_violations ++ type_violations ++ server_only_violations
  end

  defp include_names(entity_type, include) do
    Enum.flat_map(include, fn
      {name, nil} ->
        [{entity_type, name}]

      {name, %Query{} = sub_term} ->
        [{entity_type, name} | term_names(sub_term, [sub_term.entity])]
    end)
  end

  defp operand_names({:attribute, name}), do: [name]

  defp operand_names(_operand), do: []

  # The names a definition reads, each with the type it is declared on - a path resolved to the type
  # its relationships lead to: the names it computes from and compares, the names a query's
  # conditions read on every row they reach, its sort keys, the derived fields it includes and the
  # derived set a source or a quantifier ends at.
  defp read_names(owner, {:name, name}), do: [resolved_name(owner, name)]

  defp read_names(owner, {:concat, operands}), do: Enum.flat_map(operands, &read_names(owner, &1))

  defp read_names(owner, {:condition, clauses}), do: clause_names(clauses, [owner])

  defp read_names(owner, {:if, clauses, then_value, else_value}) do
    clause_names(clauses, [owner]) ++
      read_names(owner, then_value) ++ read_names(owner, else_value)
  end

  defp read_names(owner, {:query, %Query{source: {owner, chain}} = term}) do
    {hops, [set_name]} = Enum.split(chain, -1)
    set_owner_type = Entity.path_target(owner, hops)

    [{set_owner_type, set_name} | term_names(term, [term.entity, owner])]
  end

  defp read_names(_owner, {:value, _value}), do: []

  defp resolved_name(type, name) do
    {hops, [last_name]} =
      name
      |> List.wrap()
      |> Enum.split(-1)

    {Entity.path_target(type, hops), last_name}
  end

  defp same_type?({type, opts}, {type, other_opts}), do: opts[:values] == other_opts[:values]

  defp same_type?({:float, _opts}, {:integer, _other_opts}), do: true

  defp same_type?(_declared, _actual), do: false

  # A name as the row it is read on declares it: the row the clauses are about, or for
  # {:outer, levels, name} the row that many levels out, which the scope holds after it.
  defp scoped_name({:outer, levels, name}, scope), do: resolved_name(Enum.at(scope, levels), name)

  defp scoped_name(name, [type | _rows_above]), do: resolved_name(type, name)

  defp server_only?(entity_type, name),
    do: name in Entity.server_only_attribute_names(entity_type)

  # The type of a set's rows - a relationship's or a derived field's.
  defp set_type(entity_type, name) do
    case List.keyfind(entity_type.__derived__(), name, 0) do
      {_name, [target], _opts} -> target
      nil -> Entity.related_type(entity_type, name)
    end
  end

  defp source_start({:outer, levels, hops}, scope), do: {Enum.at(scope, levels), hops}

  defp source_start(hops, [type | _rows_above]), do: {type, hops}

  defp spelled_name(name) when is_list(name), do: Enum.join(name, ".")

  defp spelled_name(name), do: Atom.to_string(name)

  defp spelled_type({:enum, opts}), do: ":enum with values #{inspect(opts[:values])}"

  defp spelled_type({type, _opts}), do: inspect(type)

  defp term_names(term, scope) do
    sort_names =
      term.sort
      |> Enum.map(fn {key, _direction} -> key end)
      |> Enum.reject(&match?({:placeholder, _placeholder_name}, &1))
      |> Enum.map(&{term.entity, &1})

    clause_names(term.filter, scope) ++ sort_names ++ include_names(term.entity, term.include)
  end

  # The refusals of a definition's type, worded for where in it they are: the definition itself, a
  # branch of an if or an operand of <>.
  defp type_violations({:if, _clauses, then_value, else_value}, declared, where) do
    branch_where =
      if where == "its definition is", do: "a branch of its definition is", else: where

    type_violations(then_value, declared, branch_where) ++
      type_violations(else_value, declared, branch_where)
  end

  defp type_violations({:concat, operands} = definition, declared, where) do
    if computes?(declared, definition) do
      Enum.flat_map(operands, &type_violations(&1, {:string, []}, "an operand of its <> is"))
    else
      ["is declared #{spelled_type(declared)}, but #{where} #{computed(definition)}"]
    end
  end

  defp type_violations({:typed_name, name, actual}, declared, where) do
    if same_type?(declared, actual) do
      []
    else
      [
        "is declared #{spelled_type(declared)}, but #{where} #{spelled_name(name)}, a #{spelled_type(actual)}"
      ]
    end
  end

  defp type_violations(definition, declared, where) do
    if computes?(declared, definition) do
      []
    else
      ["is declared #{spelled_type(declared)}, but #{where} #{computed(definition)}"]
    end
  end

  # A definition with the type of every name it computes from, read on the row the name leads to.
  defp typed({:name, name}, owner), do: {:typed_name, name, field_type(owner, name)}

  defp typed({:concat, operands}, owner), do: {:concat, Enum.map(operands, &typed(&1, owner))}

  defp typed({:if, clauses, then_value, else_value}, owner),
    do: {:if, clauses, typed(then_value, owner), typed(else_value, owner)}

  defp typed(definition, _owner), do: definition

  defp value_of_type?(value, {:boolean, _opts}), do: is_boolean(value)

  defp value_of_type?(value, {:date, _opts}), do: is_struct(value, Date)

  defp value_of_type?(value, {:datetime, _opts}), do: is_struct(value, DateTime)

  defp value_of_type?(value, {:enum, opts}), do: is_atom(value) and value in opts[:values]

  defp value_of_type?(value, {:float, _opts}), do: is_number(value)

  defp value_of_type?(value, {:integer, _opts}), do: is_integer(value)

  defp value_of_type?(value, {:string, _opts}), do: is_binary(value)

  defp value_of_type?(value, {:time, _opts}), do: is_struct(value, Time)

  defp value_of_type?(value, {:uuid, _opts}), do: is_binary(value)

  defp value_of_type?(_value, {_rows_type, _opts}), do: false
end
