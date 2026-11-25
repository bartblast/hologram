defmodule Hologram.Entity.Derived.Validator do
  @moduledoc false

  # The checks a derived field's definition passes once the build resolved it - the ones its
  # declaration alone can't answer, since they read the declarations of every type it reaches.

  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Validator, as: EntityValidator
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Reflection

  @quantifiers [:all, :any, :none]

  @doc """
  Validates the derived fields of the given entity types against their given resolved definitions,
  keyed by entity type and field name: the element type of a field holding rows is an entity type,
  every definition computes what its field declares, none reads a server-only attribute - a client
  computes derived fields over the rows it holds - no derived fields read each other in a cycle, and
  none that an allow rule reads depends on a sequence number.

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
      |> Enum.concat(rule_sequence_violations(entity_types, definitions))
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

  # What a definition's answer depends on, each name with the type declaring it. Narrower than
  # read_names/2: an include adds rows beside the answer, and a sort only decides which rows the
  # query's own take, skip or single row keeps. A query orders by its own sort keys and never
  # inherits its source's, so a bound says nothing about how the set it reads was sorted.
  defp answer_reads(owner, {:name, name}), do: [resolved_name(owner, name)]

  defp answer_reads(owner, {:concat, operands}),
    do: Enum.flat_map(operands, &answer_reads(owner, &1))

  defp answer_reads(owner, {:condition, clauses}), do: clause_names(clauses, [owner])

  defp answer_reads(owner, {:if, clauses, then_value, else_value}) do
    clause_names(clauses, [owner]) ++
      answer_reads(owner, then_value) ++ answer_reads(owner, else_value)
  end

  defp answer_reads(owner, {:query, %Query{source: {owner, chain}} = term}) do
    {hops, [set_name]} = Enum.split(chain, -1)

    sort_reads =
      if bounded_term?(term),
        do: deciding_sort_keys(term),
        else: []

    [{Entity.path_target(owner, hops), set_name} | sort_reads] ++
      clause_names(term.filter, [term.entity, owner])
  end

  defp answer_reads(_owner, {:value, _value}), do: []

  defp bounded_term?(%Query{cardinality: :one}), do: true

  defp bounded_term?(%Query{skip: skip, take: take}), do: skip not in [nil, 0] or take != nil

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
        Enum.map([name | operand_names(operand)], &scoped_name(&1, scope))
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

  # Whether a definition computes what the given declared type and options hold. Nil is no value,
  # no row or no rows, whatever the field holds.
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

  # What every derived field's definition reads of other derived fields, on any type - a cycle among
  # them, more than one field or a field reading itself through a related row, is reported once, at
  # its first field, naming every field on it.
  defp cycle_violations(fields, definitions) do
    fields
    |> Map.new(fn {entity_type, name, _type, _opts} ->
      read_fields =
        entity_type
        |> read_names(Map.fetch!(definitions, {entity_type, name}))
        |> Enum.filter(fn {type, read_name} -> Derived.declared?(type, read_name) end)

      {{entity_type, name}, read_fields}
    end)
    |> Hologram.Derived.cycles()
    |> Enum.map(&cycle_violation/1)
  end

  # The sort keys that can decide which rows a bound keeps. An id is unique, so no key after it ever
  # decides.
  defp deciding_sort_keys(term) do
    term.sort
    |> Enum.take_while(fn {key, _direction} -> key != :id end)
    |> Enum.map(fn {key, _direction} -> resolved_name(term.entity, key) end)
  end

  defp declaration_location(entity_type, name) do
    case Map.fetch(entity_type.__derived_locations__(), name) do
      {:ok, {file, line}} -> "#{Path.relative_to_cwd(file)}:#{line}: "
      :error -> ""
    end
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

  # The derived fields an allow rule reads that depend on a sequence number, however many other
  # derived fields lie between. A rule naming a number outright is refused with the rule (see
  # Hologram.Policy.Validator), and one through a derived set only shows in its resolved definition.
  defp rule_sequence_violations(entity_types, definitions) do
    entity_types
    |> Enum.flat_map(fn entity_type ->
      for {operation, _to, _via, predicates, _name, _fields} <- entity_type.__policies__(),
          {type, name} <-
            clause_names(rule_clauses(entity_type, operation, predicates), [entity_type]),
          Derived.declared?(type, name),
          {read_type, read_name} <- sequence_reads({type, name}, definitions) do
        {type, name,
         "derived field #{inspect(name)} in #{inspect(type)} reads #{inspect(read_type)}.#{read_name}, a sequence number, and an allow rule of #{inspect(entity_type)} reads the field. A browser and the server read a sequence number differently until it's final, so no rule can depend on it"}
      end
    end)
    |> Enum.uniq()
  end

  # An update rule's clauses read the row after the change through new(), resolved one row above
  # the rule's own - spelled here as the same names of the rule's row, which has the same type.
  defp rule_clauses(entity_type, operation, predicates) do
    entity_type
    |> Policy.condition_clauses(operation, predicates)
    |> Policy.stored_spelling()
  end

  defp same_type?({type, opts}, {type, other_opts}), do: opts[:values] == other_opts[:values]

  defp same_type?({:float, _opts}, {:integer, _other_opts}), do: true

  defp same_type?(_declared, _actual), do: false

  # A name as the row it is read on declares it: the row the clauses are about, or for
  # {:outer, levels, name} the row that many levels out, which the scope holds after it.
  defp scoped_name({:outer, levels, name}, scope), do: resolved_name(Enum.at(scope, levels), name)

  defp scoped_name(name, [type | _rows_above]), do: resolved_name(type, name)

  # The sequence numbers the answer of the given derived field depends on, itself or through the
  # derived fields it reads.
  defp sequence_reads(field, definitions) do
    {sequences, _visited} = sequence_reads(field, definitions, MapSet.new())

    Enum.uniq(sequences)
  end

  # Each field is walked once, so fields sharing what they read don't multiply the walk.
  defp sequence_reads({type, _name} = field, definitions, visited) do
    if MapSet.member?(visited, field) do
      {[], visited}
    else
      {sequences, others} =
        type
        |> answer_reads(Map.fetch!(definitions, field))
        |> Enum.split_with(fn {_read_type, name} -> Entity.sequence_attribute?(name) end)

      {through, walked} =
        others
        |> Enum.filter(fn {read_type, name} -> Derived.declared?(read_type, name) end)
        |> Enum.flat_map_reduce(MapSet.put(visited, field), &sequence_reads(&1, definitions, &2))

      {sequences ++ through, walked}
    end
  end

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
    sort_names = Enum.map(term.sort, fn {key, _direction} -> {term.entity, key} end)

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

  # An integer column holds 64 bits, so a query reading a larger value would fail when it runs.
  defp type_violations({:value, value}, {:integer, _opts} = declared, where)
       when is_integer(value) do
    if EntityValidator.attribute_value_valid?(value, :integer) do
      []
    else
      [
        "is declared #{spelled_type(declared)}, but #{where} the value #{value}, which doesn't fit in 64 bits"
      ]
    end
  end

  # A float column stops at about 1.8e308, so a query reading a larger integer would fail when it
  # runs, and a browser would read it as Infinity.
  defp type_violations({:value, value}, {:float, _opts} = declared, where)
       when is_integer(value) do
    case Codec.decode_json(value, :float) do
      {:ok, _float} ->
        []

      :error ->
        [
          "is declared #{spelled_type(declared)}, but #{where} the value #{value}, which doesn't fit in a float"
        ]
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
