defmodule Hologram.Entity.Derived do
  @moduledoc false

  # A derived field's definition: what its function builds when its arguments stand for the fields
  # of a row nobody has read yet. The function runs once, with every field it names replaced by a
  # stand-in - a query over the row's set, a name of the row a condition compares with, a row to read
  # further through - and what comes back is a plain description every executor evaluates for each
  # row the way it evaluates a filter.

  alias Hologram.Query
  alias Hologram.Query.RowField
  alias Hologram.Query.Stage
  alias Hologram.Reflection

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
  Returns the stand-in for the given path of fields of a row of the given owning entity type, read
  by a derived field's function: a query over the set a path ends at - a relationship's or a derived
  field's - a row field for one ending at an attribute, a reference field or a derived field holding
  a value, and a row reference for one ending at a related row. A set before the path's end makes
  the rows every path reaches one set.

  Raises ArgumentError when the path names what the type does not declare, reads past an attribute
  or a derived field, ends at an attribute through a set, or ends at a derived field holding one
  row.
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
  Puts the given definitions, keyed by entity type and field name, where definition/2 reads them.
  """
  @spec put_definitions(%{{module, atom} => definition}) :: :ok
  def put_definitions(definitions) do
    Enum.each(definitions, fn {{entity_type, name}, definition} ->
      :persistent_term.put(table_key(entity_type, name), definition)
    end)
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

    normalized(definition)
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

  defp derived_kind({_name, [_target], _opts}), do: :set

  defp derived_kind({_name, type, _opts}) do
    if Reflection.alias?(type), do: :derived_row, else: :value
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

  defp name_of([name]), do: name

  defp name_of(path), do: path

  defp normalized({:query, term}), do: {:query, Stage.normalize(term)}

  defp normalized({:concat, operands}), do: {:concat, Enum.map(operands, &normalized/1)}

  defp normalized({:if, clauses, then_value, else_value}),
    do: {:if, clauses, normalized(then_value), normalized(else_value)}

  defp normalized(definition), do: definition

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

  @spec raise_unknown_field!(module, atom, list(atom), String.t()) :: no_return
  defp raise_unknown_field!(entity_type, name, path, kind) do
    raise ArgumentError,
      message:
        "#{Enum.join(path, ".")} names #{inspect(name)}, which is not #{kind} of #{inspect(entity_type)}"
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

  defp table_key(entity_type, name), do: {__MODULE__, entity_type, name}
end
