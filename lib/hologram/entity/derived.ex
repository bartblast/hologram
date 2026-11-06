defmodule Hologram.Entity.Derived do
  @moduledoc false

  # A derived field's definition: what its function builds when its arguments stand for the fields
  # of a row nobody has read yet. The function runs once, with every field it names replaced by a
  # stand-in - a query over the row's set, a name of the row a condition compares with, a row to read
  # further through - and what comes back is a plain description every executor evaluates for each
  # row the way it evaluates a filter.

  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Query.RowField
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  @quantifiers [:all, :any, :none]

  defmodule RowRef do
    @moduledoc false

    # Stands for a related row a field of the row leads to - a to-one or an inverse holding one row
    # - read only to reach further: one of its attributes, or a set of its.
    @enforce_keys [:owner, :path]

    defstruct [:owner, :path]

    @type t :: %__MODULE__{owner: module, path: list(atom)}
  end

  @typedoc """
  What a derived field computes for a row: a value, a name of the row - an attribute, a reference
  field, a path to an attribute of a related row - strings joined, one of two expressions picked by
  a condition, whether a condition holds, or a query over the row's sets, a count, one row or a set.
  """
  @type definition ::
          {:value, any}
          | {:name, Query.name()}
          | {:concat, list(definition)}
          | {:if, list(Query.clause()), definition, definition}
          | {:condition, list(Query.clause())}
          | {:query, Query.t()}

  @doc """
  Returns the definition joining the given operands as strings, each lowered as a body's result is.
  """
  @spec concat(list(any)) :: definition
  def concat(operands), do: {:concat, Enum.map(operands, &lower/1)}

  @doc """
  Returns the definition of whether the given predicates, in the filter data form, hold for a row of
  the given owning entity type - checked as a filter of that type is.

  Raises ArgumentError when the predicates name what the type does not declare or compare what does
  not compare.
  """
  @spec condition(module, Query.predicates()) :: definition
  def condition(owner, predicates), do: {:condition, Stage.predicate_triples!(owner, predicates)}

  @doc """
  Returns whether the given name is a derived field of the given entity type.
  """
  @spec declared?(module, atom) :: boolean
  def declared?(entity_type, name), do: List.keymember?(entity_type.__derived__(), name, 0)

  @doc """
  Returns the definition of the given derived field of the given entity type, as the build resolved
  it - the one source of definitions at runtime, put by the build in its own VM and by the query
  cache at boot.

  Raises ArgumentError when no definition was put for the field.
  """
  @spec definition(module, atom) :: definition
  def definition(entity_type, name) do
    key = table_key(entity_type, name)

    case :persistent_term.get(key, nil) do
      nil ->
        raise ArgumentError,
          message:
            "no definition for #{inspect(entity_type)}.#{name} - the Hologram compile resolves derived fields"

      definition ->
        definition
    end
  end

  @doc """
  Returns the references - {relationship names, name} pairs - the given ones read on a row of the
  given entity type once every derived field holding a value among them is read through its
  definition, written in place: a derived name is replaced by what its definition reads, on the row
  it is read on, recursively, and a derived field reached again inside its own reads adds nothing.

  A definition is resolved natively, as resolve/2 resolves it: the fields a policy condition reads
  outside any quantifier call no query builder, and a policy is validated before the build
  resolves any definition. One reading a related set is refused there before anything expands one,
  so a count reads nothing here - what a quantifier's condition reads is expanded by set_reads/2.
  """
  @spec expanded_references(module, list({list(atom), atom})) :: list({list(atom), atom})
  def expanded_references(entity_type, references) do
    entity_type
    |> expanded_references(references, [])
    |> Enum.uniq()
  end

  @doc """
  Returns the stand-in for the given path of fields of a row of the given owning entity type, read
  by a derived field's function: a query over the set a path ends at - a relationship's or a derived
  field's - a row field for one ending at an attribute, a reference field or a derived field holding
  a value, and a row reference for one ending at a related row. A set before the path's end makes
  the rows every path reaches one set.

  Raises ArgumentError when the path names what the type does not declare, reads past an attribute
  or a derived field, ends at an attribute through a set or through an inverse - a value is read
  through to-one relationships holding their reference, as a condition's path is - or ends at a
  derived field holding one row.
  """
  @spec field(module, list(atom)) :: Query.t() | RowField.t() | RowRef.t()
  def field(owner, path) do
    {hops, [last]} = Enum.split(path, -1)

    {end_type, through_set?} = path_end(owner, hops, path)

    case {field_kind(end_type, last), through_set?} do
      {:set, _through_set?} ->
        Stage.sourced(owner, path)

      {:row, false} ->
        %RowRef{owner: owner, path: path}

      {:value, false} ->
        validate_stored_hops!(owner, hops)

        %RowField{owner: owner, name: name_of(path)}

      {:derived_row, _through_set?} ->
        raise ArgumentError,
          message:
            "#{Enum.join(path, ".")} is a derived field holding one row - include it, or read the rows it is computed from"

      {nil, _through_set?} ->
        raise_unknown_field!(end_type, last, path, "a field")

      {_kind, true} ->
        raise ArgumentError,
          message:
            "#{Enum.join(path, ".")} reads through a set to one value per row of it - a derived field reads a set's rows with a query, or one value of the row through to-one relationships"
    end
  end

  @doc """
  Returns the definition picking the first of the given expressions when the given condition holds
  for the row and the second when it does not, each lowered as a body's result is.
  """
  @spec if_value(definition, any, any) :: definition
  def if_value({:condition, clauses}, then_value, else_value),
    do: {:if, clauses, lower(then_value), lower(else_value)}

  @doc """
  Returns the given result of a derived field's function as a definition: a query over the row's
  sets as is, a row field as the name it stands for, an expression concat/1, if_value/3 or
  condition/2 built as is, and a plain value as a value.

  Raises ArgumentError on a query that starts from an entity type rather than from the row, and on
  a related row, which is the relationship itself rather than anything computed from it.
  """
  @spec lower(any) :: definition
  def lower(%Query{source: {_owner, _chain}} = term), do: {:query, term}

  def lower(%Query{entity: entity_type}) do
    raise ArgumentError,
      message:
        "a derived field's query starts from a relationship of the row, got a query of every #{inspect(entity_type)} - read the rows through an argument naming the relationship"
  end

  def lower(%RowField{name: name}), do: {:name, name}

  def lower({:concat, operands} = expression) when is_list(operands), do: expression

  def lower({:if, clauses, _then_value, _else_value} = expression) when is_list(clauses),
    do: expression

  def lower({:condition, clauses} = expression) when is_list(clauses), do: expression

  def lower(%RowRef{path: path}) do
    raise ArgumentError,
      message:
        "#{Enum.join(path, ".")} is a related row - include the relationship, or derive one of its attributes: #{Enum.join(path, ".")}.<attribute>"
  end

  def lower(value)
      when is_atom(value) or is_number(value) or is_binary(value) or is_struct(value, Date) or
             is_struct(value, DateTime) or is_struct(value, Time),
      do: {:value, value}

  def lower(value) do
    raise ArgumentError,
      message:
        "a derived field computes a value of its type, a field of the row or a query over its rows, got: #{inspect(value)}"
  end

  @doc """
  Returns the canonical form of the given definition: every query in it normalized, read in its
  set's declared order when it states none.
  """
  @spec normalize(definition) :: definition
  def normalize({:query, term}), do: {:query, Stage.normalize(term)}

  def normalize({:concat, operands}), do: {:concat, Enum.map(operands, &normalize/1)}

  def normalize({:if, clauses, then_value, else_value}),
    do: {:if, clauses, normalize(then_value), normalize(else_value)}

  def normalize(definition), do: definition

  @doc """
  Returns the type a path of relationships and derived fields holding rows leads to from a row of
  the given entity type - the type of the rows at its end. See related_type/2.
  """
  @spec path_target(module, list(atom)) :: module
  def path_target(entity_type, names), do: Enum.reduce(names, entity_type, &related_type(&2, &1))

  @doc """
  Puts the given definitions, keyed by entity type and field name, where definition/2 reads them.
  """
  @spec put_definitions(%{{module, atom} => definition}) :: :ok
  def put_definitions(definitions) do
    Enum.each(definitions, fn {{entity_type, name}, definition} ->
      :persistent_term.put(table_key(entity_type, name), definition)
    end)
  end

  @doc """
  Returns the derived fields the given filter clauses read on a row of the given entity type, each
  as `{entity type, name}` once, sorted: every derived field they name or run through, and every
  one those fields' definitions read in turn, on the rows they are read on - each read through its
  definition as the build resolved it, as `set_reads/2` reads a quantifier's condition.
  """
  @spec read_fields(module, list(Query.clause())) :: list({module, atom})
  def read_fields(entity_type, clauses) do
    references = Stage.predicate_references(clauses)
    chains = Stage.relationship_chains(clauses)
    {_references, _chains, fields} = reads(entity_type, references, chains, true, [])

    fields
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns the type of the rows the given relationship or derived field holding rows leads to from a
  row of the given entity type - a relationship's target, a derived field's declared row type.
  """
  @spec related_type(module, atom) :: module
  def related_type(entity_type, name) do
    case List.keyfind(entity_type.__derived__(), name, 0) do
      {_name, [target], _opts} -> target
      {_name, target, _opts} -> target
      nil -> Entity.related_type(entity_type, name)
    end
  end

  @doc """
  Returns the message refusing a write to the given derived field of the given entity type - every
  write path refuses one in these words.
  """
  @spec read_only_message(module, atom) :: String.t()
  def read_only_message(entity_type, name) do
    "#{inspect(name)} is a derived field of #{inspect(entity_type)} - it's computed from its definition, so it's read-only"
  end

  @doc """
  Resolves the definition of the given derived field of the given entity type by running its
  function over stand-ins for the row's fields, normalized: a query is put in its canonical form,
  read in its set's declared order when it states none.

  Raises Hologram.CompileError, located at the field's declaration, when the definition cannot be
  built - a name its related types do not declare, a stage refusing what it is given.
  """
  @spec resolve(module, atom) :: definition
  def resolve(entity_type, name) do
    definition = entity_type.__derived_definition__(name)

    normalize(definition)
  rescue
    error in ArgumentError ->
      {file, line} = Map.fetch!(entity_type.__derived_locations__(), name)

      reraise Hologram.CompileError,
              [
                message:
                  "invalid derived field #{inspect(name)} in #{inspect(entity_type)} - #{Exception.message(error)}",
                file: file,
                line: line
              ],
              __STACKTRACE__
  end

  @doc """
  Returns the term the rows the given field of the given entity type holds are read with, given the
  term the field is included with: a relationship's rows as included, a derived field's embedding
  what its definition includes - every query it may choose included - beside the nested includes
  the field is included with. Where both include one relationship, the definition's include is kept
  and gains what the other includes.
  """
  @spec rows_term(module, atom, Query.t()) :: Query.t()
  def rows_term(entity_type, name, included_term) do
    if declared?(entity_type, name) do
      include =
        entity_type
        |> definition(name)
        |> definition_queries()
        |> Enum.reduce(included_term.include, &merged_include(&1.include, &2))

      %{included_term | include: include}
    else
      included_term
    end
  end

  @doc """
  Returns what makes the given derived field holding a value of the given entity type read a
  related set, spelled for a refusal - a count its definition computes, a query builder it calls,
  another field it reads that does - or nil when it reads none. Its definition is resolved
  natively, as `resolve/2` resolves it, so a build can ask before it resolves any. A field reached
  again inside its own reads is a cycle, refused at the build, and adds nothing here.
  """
  @spec set_reading(module, atom) :: String.t() | nil
  def set_reading(entity_type, name), do: set_reading(entity_type, name, [])

  @doc """
  Returns the references - {relationship names, name} pairs - and the chains of relationships the
  given filter clauses read on a row of the given entity type (see
  `Hologram.Query.Stage.predicate_references/1` and `Hologram.Query.Stage.relationship_chains/1`),
  with every one running through a derived field holding rows written in terms of what that
  field's definition reads, as the build resolved it: the reference or chain goes through its
  queries' own chains in its place, and its definition's reads join them - the chains its queries
  read, the names their filters and sort keys read and the sets their quantifiers follow, and what
  the conditions choosing between them read. A derived field holding a value that a quantifier's
  condition or a definition reads is written in terms of its definition the same way, a count's
  chain and filter among its reads. A derived field reached again inside its own reads adds nothing.

  A name the clauses read outside any quantifier stays as it is, for `expanded_references/2` to
  expand natively.
  """
  @spec set_reads(module, list(Query.clause())) :: {list({list(atom), atom}), list(list(atom))}
  def set_reads(entity_type, clauses) do
    {references, chains, _fields} = clause_walk(entity_type, clauses)

    {Enum.uniq(references), Enum.uniq(chains)}
  end

  @doc """
  Returns whether the given relationship names, read from a row of the given entity type, run
  through a derived field holding rows.
  """
  @spec through_set?(module, list(atom)) :: boolean
  def through_set?(entity_type, names), do: derived_split(entity_type, names) != nil

  @doc """
  Returns whether the given name is a derived field of the given entity type holding a value.
  """
  @spec value_field?(module, atom) :: boolean
  def value_field?(entity_type, name) do
    case List.keyfind(entity_type.__derived__(), name, 0) do
      {_name, type, _opts} -> derived_kind({name, type, []}) == :value
      nil -> false
    end
  end

  defp chain_reads(entity_type, chain, walked) do
    case derived_split(entity_type, chain) do
      nil ->
        {[], [chain], []}

      {before, owner_type, name, later_names} ->
        through_reads(entity_type, before, owner_type, name, walked, fn set_chain ->
          {[], [set_chain ++ later_names], []}
        end)
    end
  end

  defp clause_reads(clauses, prefixes) do
    {Stage.predicate_references(clauses, prefixes), Stage.relationship_chains(clauses, prefixes)}
  end

  # What filter clauses read through derived fields - references, chains and the derived fields
  # walked - the names inside quantifiers read as a definition's are.
  defp clause_walk(entity_type, clauses) do
    quantified_references =
      clauses
      |> quantifier_clauses()
      |> Stage.predicate_references()

    own_references = Stage.predicate_references(clauses) -- quantified_references
    chains = Stage.relationship_chains(clauses)

    joined_walks([
      reads(entity_type, own_references, chains, false, []),
      reads(entity_type, quantified_references, [], true, [])
    ])
  end

  defp definition_queries({:if, _clauses, then_value, else_value}) do
    definition_queries(then_value) ++ definition_queries(else_value)
  end

  defp definition_queries({:query, term}), do: [term]

  defp definition_queries(_definition), do: []

  # What a definition reads off the row the given relationships lead to from the row reads are
  # written for: references and chains, in that row's terms.
  defp definition_reads({:concat, operands}, prefix) do
    operands
    |> Enum.map(&definition_reads(&1, prefix))
    |> joined_reads()
  end

  defp definition_reads({:condition, clauses}, prefix), do: clause_reads(clauses, [prefix])

  defp definition_reads({:if, clauses, then_value, else_value}, prefix) do
    joined_reads([
      clause_reads(clauses, [prefix]),
      definition_reads(then_value, prefix),
      definition_reads(else_value, prefix)
    ])
  end

  defp definition_reads({:name, path}, prefix) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    {[{prefix ++ relationship_names, name}], []}
  end

  defp definition_reads({:name, name}, prefix), do: {[{prefix, name}], []}

  # A query's rows are read off the set its chain leads to, with the row the field belongs to above
  # them, and ordered by its sort keys.
  defp definition_reads({:query, %{source: {_owner_type, chain}} = term}, prefix) do
    set_prefix = prefix ++ chain
    {filter_references, filter_chains} = clause_reads(term.filter, [set_prefix, prefix])
    sort_references = Enum.map(term.sort, fn {name, _direction} -> {set_prefix, name} end)

    {filter_references ++ sort_references, [set_prefix | filter_chains]}
  end

  defp definition_reads({:value, _value}, _prefix), do: {[], []}

  # The value fields a definition reads directly, on its own row - a count reads none of them.
  defp definition_references({:concat, operands}),
    do: Enum.flat_map(operands, &definition_references/1)

  defp definition_references({:condition, clauses}), do: Stage.predicate_references(clauses)

  defp definition_references({:if, clauses, then_value, else_value}) do
    Stage.predicate_references(clauses) ++
      definition_references(then_value) ++ definition_references(else_value)
  end

  defp definition_references({:name, name}), do: [reference(name)]

  defp definition_references({:query, _term}), do: []

  defp definition_references({:value, _value}), do: []

  defp derived_kind({_name, [_target], _opts}), do: :set

  defp derived_kind({_name, type, _opts}) do
    if Reflection.alias?(type), do: :derived_row, else: :value
  end

  # Splits relationship names read from a row of the given type at the first derived field holding
  # rows: the names before it, the type it is declared on, its name and the names after it - nil
  # when the names run through relationships alone.
  defp derived_split(_entity_type, []), do: nil

  defp derived_split(entity_type, [name | later_names]) do
    if declared?(entity_type, name) do
      {[], entity_type, name, later_names}
    else
      related_type = Entity.related_type(entity_type, name)

      case derived_split(related_type, later_names) do
        nil -> nil
        {before, owner_type, field_name, rest} -> {[name | before], owner_type, field_name, rest}
      end
    end
  end

  defp expanded_references(entity_type, references, visited) do
    Enum.flat_map(references, fn {relationship_names, name} = reference ->
      read_type = Entity.path_target(entity_type, relationship_names)
      field = {read_type, name}

      cond do
        not value_field?(read_type, name) ->
          [reference]

        field in visited ->
          []

        true ->
          read_references =
            read_type
            |> resolve(name)
            |> definition_references()

          read_type
          |> expanded_references(read_references, [field | visited])
          |> Enum.map(&prefixed_reference(&1, relationship_names))
      end
    end)
  end

  # What the last name of a path reads: a set, one related row, a value - an attribute, a reference
  # field or a derived field holding one - or one row a derived field computes.
  defp field_kind(entity_type, name) do
    case relationship_kind(entity_type, name) do
      {kind, _target} ->
        kind

      nil ->
        cond do
          name in field_names(entity_type) -> :value
          derived = List.keyfind(entity_type.__derived__(), name, 0) -> derived_kind(derived)
          true -> nil
        end
    end
  end

  defp field_names(entity_type) do
    reference_names =
      entity_type.__relationships__()
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Enum.map(fn {name, _type, _opts} -> String.to_existing_atom("#{name}_id") end)

    entity_type.__attributes__()
    |> Enum.concat(entity_type.__system_attributes__())
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.concat(reference_names)
  end

  defp joined_reads(reads) do
    Enum.reduce(reads, {[], []}, fn {references, chains}, {acc_references, acc_chains} ->
      {acc_references ++ references, acc_chains ++ chains}
    end)
  end

  defp joined_walks(walks) do
    Enum.reduce(walks, {[], [], []}, fn {references, chains, fields},
                                        {acc_refs, acc_chains, acc_fields} ->
      {acc_refs ++ references, acc_chains ++ chains, acc_fields ++ fields}
    end)
  end

  defp merged_include(kept_include, other_include) do
    Map.merge(kept_include, other_include, fn
      _name, nil, nil ->
        nil

      _name, kept_term, other_term ->
        %{kept_term | include: merged_include(kept_term.include, other_term.include)}
    end)
  end

  defp name_of([name]), do: name

  defp name_of(path), do: path

  # The type a path's relationships lead to, and whether a set lies along them.
  defp path_end(owner, hops, path) do
    Enum.reduce(hops, {owner, false}, fn hop, {entity_type, set?} ->
      case relationship_kind(entity_type, hop) do
        {:set, target} -> {target, true}
        {:row, target} -> {target, set?}
        nil -> raise_unknown_field!(entity_type, hop, path, "a relationship")
      end
    end)
  end

  defp prefixed_reference({relationship_names, name}, prefix),
    do: {prefix ++ relationship_names, name}

  defp quantifier_clauses(clauses) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} -> Enum.flat_map(alternatives, &quantifier_clauses/1)
      {quantifier, {_source, _clauses}} = clause when quantifier in @quantifiers -> [clause]
      _triple -> []
    end)
  end

  @spec raise_unknown_field!(module, atom, list(atom), String.t()) :: no_return
  defp raise_unknown_field!(entity_type, name, path, kind) do
    raise ArgumentError,
      message:
        "#{Enum.join(path, ".")} names #{inspect(name)}, which is not #{kind} of #{inspect(entity_type)}"
  end

  # What the given references and chains read once every derived field holding rows they run
  # through is read through its definition, and - inside a quantifier's condition or a definition -
  # every derived field holding a value they name is too, with the derived fields read so. The
  # fields being walked are given.
  defp reads(entity_type, references, chains, inside?, walked) do
    reference_reads = Enum.map(references, &reference_reads(entity_type, &1, inside?, walked))
    chain_reads = Enum.map(chains, &chain_reads(entity_type, &1, walked))

    joined_walks(reference_reads ++ chain_reads)
  end

  defp reference(path) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    {relationship_names, name}
  end

  defp reference(name), do: {[], name}

  defp reference_reads(entity_type, {relationship_names, name} = reference, inside?, walked) do
    case derived_split(entity_type, relationship_names) do
      nil ->
        read_type = path_target(entity_type, relationship_names)
        field = {read_type, name}

        if inside? and value_field?(read_type, name) and field not in walked do
          {field_references, field_chains} =
            read_type
            |> definition(name)
            |> definition_reads(relationship_names)

          {references, chains, fields} =
            reads(entity_type, field_references, field_chains, true, [field | walked])

          {references, chains, [field | fields]}
        else
          {[reference], [], []}
        end

      {before, owner_type, set_name, later_names} ->
        through_reads(entity_type, before, owner_type, set_name, walked, fn set_chain ->
          {[{set_chain ++ later_names, name}], [], []}
        end)
    end
  end

  # A stored relationship or an inverse, as what reading it gives: the rows of a set, or one row.
  defp relationship_kind(entity_type, name) do
    definitions =
      Enum.concat(entity_type.__relationships__(), entity_type.__inverse_relationships__())

    case List.keyfind(definitions, name, 0) do
      {_name, [target], _opts} -> {:set, target}
      {_name, target, _opts} -> {:row, target}
      nil -> nil
    end
  end

  defp set_reading(entity_type, name, visited) do
    field = {entity_type, name}

    cond do
      field in visited ->
        nil

      name in entity_type.__derived_builder_calls__() ->
        "calls a query builder"

      true ->
        entity_type
        |> resolve(name)
        |> set_reading_of(entity_type, [field | visited])
    end
  end

  defp set_reading_of({:concat, operands}, entity_type, visited) do
    Enum.find_value(operands, &set_reading_of(&1, entity_type, visited))
  end

  defp set_reading_of({:condition, clauses}, entity_type, visited) do
    clauses
    |> Stage.predicate_references()
    |> set_reading_through(entity_type, visited)
  end

  defp set_reading_of({:if, clauses, then_value, else_value}, entity_type, visited) do
    references = Stage.predicate_references(clauses)

    set_reading_through(references, entity_type, visited) ||
      set_reading_of(then_value, entity_type, visited) ||
      set_reading_of(else_value, entity_type, visited)
  end

  defp set_reading_of({:name, name}, entity_type, visited) do
    {relationship_names, [read_name]} =
      name
      |> List.wrap()
      |> Enum.split(-1)

    set_reading_through([{relationship_names, read_name}], entity_type, visited)
  end

  defp set_reading_of({:query, %{source: {_owner, chain}}}, _entity_type, _visited) do
    "counts #{Enum.join(chain, ".")}"
  end

  defp set_reading_of({:value, _value}, _entity_type, _visited), do: nil

  # The first of the given references reaching a derived field that reads a related set, spelled.
  defp set_reading_through(references, entity_type, visited) do
    Enum.find_value(references, fn {relationship_names, name} ->
      read_type = Entity.path_target(entity_type, relationship_names)

      if value_field?(read_type, name) do
        read_type
        |> set_reading(name, visited)
        |> spelled_reading(List.insert_at(relationship_names, -1, name))
      end
    end)
  end

  defp spelled_reading(nil, _path), do: nil

  defp spelled_reading(reading, [name]), do: "reads #{inspect(name)}, which #{reading}"

  defp spelled_reading(reading, path), do: "reads #{Stage.inspect_name(path)}, which #{reading}"

  defp table_key(entity_type, name), do: {__MODULE__, entity_type, name}

  # What a read through the given derived field holding rows reads: the given read made of each
  # chain its queries read in its place, and what its definition reads.
  defp through_reads(entity_type, before, owner_type, name, walked, read_through) do
    field = {owner_type, name}

    if field in walked do
      {[], [], []}
    else
      definition = definition(owner_type, name)

      {through_refs, through_chains, _fields} =
        definition
        |> definition_queries()
        |> Enum.map(fn %{source: {_owner_type, chain}} -> read_through.(before ++ chain) end)
        |> joined_walks()

      {definition_refs, definition_chains} = definition_reads(definition, before)

      # Past the field a chain can meet it again on other rows, which is no cycle - only what the
      # definition reads is walked inside it.
      {references, chains, fields} =
        joined_walks([
          reads(entity_type, through_refs, through_chains, true, walked),
          reads(entity_type, definition_refs, definition_chains, true, [field | walked])
        ])

      {references, chains, [field | fields]}
    end
  end

  # A value of a related row is read through to-one relationships holding their reference, the hops
  # every executor follows a path's reference fields through, as a condition's path is.
  defp validate_stored_hops!(owner, hops) do
    Enum.reduce(hops, owner, fn hop, entity_type ->
      if Entity.inverse_relationship(entity_type, hop) do
        raise ArgumentError,
          message:
            "#{inspect(hop)} is an inverse relationship in #{inspect(entity_type)} - a derived field reads a related row's value through to-one relationships that hold their reference"
      end

      Entity.related_type(entity_type, hop)
    end)
  end
end
