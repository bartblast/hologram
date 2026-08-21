defmodule Hologram.Query.Interpreter do
  @moduledoc false

  # The reference implementation of the query kernel: the locked operator set evaluated over
  # plain Elixir data rather than compiled to SQL.
  #
  # It exists to be proven identical to the database executor in ExUnit, over the same rows -
  # which is what lets the client's hand-written JavaScript kernel be proven identical in turn,
  # against this rather than against a database. Two implementations of a small frozen surface,
  # each pinned to the one before it.
  #
  # Never bundled. Nothing a client can reach calls it, and the client would gain nothing by
  # running it: it reads plain Elixir terms, where the browser holds the wire's own values.

  alias Hologram.DB.SortKey

  @doc """
  Runs the given normalized query term over the given rows and returns what the database would
  return for it - a list of entity structs, one struct or nil for a single-result query, an
  integer for a counting one.

  The rows are the client's whole database rather than a table: `:rows` maps each entity type to
  its rows by id, and `:facts` pairs the ids a to-many relationship holds. A query reads the
  table of its own entity type and reaches the rest through what it includes.

  `:actor_user_id` in the options is who is asking, for the predicates that name the acting user.
  An anonymous one matches nothing, the way an actor-referencing statement matches nothing when
  there is no actor to compare against. `:bindings` gives the values of the term's placeholders, every
  one of which the term names, and none of which may be nil - neither as a value nor as an element
  of a list - which is what the database refuses one for.

  Raises ArgumentError on a missing or nil binding.
  """
  @spec run(%{atom => any}, %{atom => any}, keyword) :: list(struct) | struct | integer | nil
  def run(term, database, opts \\ []) do
    ranks = predicate_ranks(term)

    rows =
      database
      |> table(term.entity)
      |> Enum.filter(&matches?(&1, term.filter, opts, ranks))

    case term.cardinality do
      # A count counts what the query evaluates to, so the bounds apply before it is taken -
      # and never the order, which cannot change how many there are. A counting query carries no
      # includes either: an embedded entity cannot change how many there are of what holds it.
      :count ->
        rows
        |> bound(term)
        |> length()

      :one ->
        rows
        |> arrange(term)
        |> List.first()
        |> embed(term, database, opts)

      :set ->
        rows
        |> arrange(term)
        |> Enum.map(&embed(&1, term, database, opts))
    end
  end

  defp arrange(rows, term) do
    rows
    |> sort(term.order_by, term.entity)
    |> bound(term)
  end

  defp bound(rows, term) do
    rows
    |> Enum.drop(term.offset || 0)
    |> take(term.limit)
  end

  # Values of one kind, compared the way that kind is ordered rather than the way its
  # representation happens to sort: two dates are two maps to a term comparison, which would
  # read their days before their years.
  defp compare_values(%Date{} = left, %Date{} = right), do: Date.compare(left, right)

  defp compare_values(%DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right)
  end

  defp compare_values(left, right) when left < right, do: :lt

  defp compare_values(left, right) when left > right, do: :gt

  defp compare_values(_left, _right), do: :eq

  # Missing values are placed the way the database places them - last when ascending, first when
  # descending - so a page reading its own rows shows them where the server put them.
  defp compare_keys(nil, nil, _direction, _ranks), do: :eq

  defp compare_keys(nil, _right, :asc, _ranks), do: :gt

  defp compare_keys(_left, nil, :asc, _ranks), do: :lt

  defp compare_keys(nil, _right, :desc, _ranks), do: :lt

  defp compare_keys(_left, nil, :desc, _ranks), do: :gt

  defp compare_keys(left, right, direction, ranks) do
    result = compare_ordering_values(left, right, ranks)

    if direction == :desc do
      flip(result)
    else
      result
    end
  end

  # Strings order by the key derived from them and then by themselves, which is the pair of
  # columns the database orders them by - the key carries the practical order, and the value
  # behind it settles what the key cannot, since the key is a bounded prefix of it.
  defp compare_ordering_values(left, right) when is_binary(left) and is_binary(right) do
    case compare_values(SortKey.compute(left), SortKey.compute(right)) do
      :eq -> compare_values(left, right)
      result -> result
    end
  end

  defp compare_ordering_values(left, right), do: compare_values(left, right)

  defp compare_ordering_values(left, right, nil), do: compare_ordering_values(left, right)

  # An enum value orders by its position in the declared list, which is the order the database
  # holds the type in - so what compares is the pair of positions rather than the labels. A value
  # the list does not hold is a bug surfacing rather than a case to place: the database refuses
  # to store one, and the lookup raises on it here.
  defp compare_ordering_values(left, right, ranks) do
    compare_values(Map.fetch!(ranks, left), Map.fetch!(ranks, right))
  end

  # A relationship the query asked for is filled from the rest of the database - a to-one by
  # following the id its row carries, a to-many by reading the pairs. What it did not ask for
  # keeps the sentinel saying so, which is a different answer from an empty one.
  defp embed(nil, _term, _database, _opts), do: nil

  defp embed(row, term, database, opts) do
    Enum.reduce(term.include, row, fn {name, sub_term}, embedded ->
      kind = relationship_kind(term.entity, name)

      Map.put(embedded, name, embedded_value(row, name, kind, sub_term, database, opts))
    end)
  end

  defp embedded_value(row, name, :to_one, sub_term, database, opts) do
    reference = Map.fetch!(row, reference_field(name))

    database
    |> table(sub_term.entity)
    |> Enum.find(&(&1.id == reference))
    |> embed(sub_term, database, opts)
  end

  # A to-many is the rows the pairs name, put through the clauses the include carries - a set of
  # its own, filtered, ordered and bounded like any other. A pair naming a row the database does
  # not hold is passed over: a fill arrives in pieces, and a parent can be told about a child
  # that has not landed yet.
  defp embedded_value(row, name, :to_many, sub_term, database, opts) do
    target_ids = Map.get(database.facts, {row.__struct__, name, row.id}, [])
    targets = table(database, sub_term.entity)
    ranks = predicate_ranks(sub_term)

    target_ids
    |> Enum.map(fn target_id -> Enum.find(targets, &(&1.id == target_id)) end)
    |> Enum.filter(&(not is_nil(&1) and matches?(&1, sub_term.filter, opts, ranks)))
    |> arrange(sub_term)
    |> Enum.map(&embed(&1, sub_term, database, opts))
  end

  # What an enum compares by: each declared value against its position in the list the entity
  # declares, built once per run and only for the names that need it - the ordering keys and the
  # filtered attributes alike. A name of any other type is absent, and its comparison is the
  # ordinary one.
  defp enum_ranks(entity_type, names) do
    entity_type.__attributes__()
    |> Enum.filter(fn {name, type, _opts} -> type == :enum and name in names end)
    |> Map.new(fn {name, _type, opts} ->
      ranks =
        opts
        |> Keyword.fetch!(:values)
        |> Enum.with_index()
        |> Map.new()

      {name, ranks}
    end)
  end

  defp equal?(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq

  defp equal?(%DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right) == :eq
  end

  defp equal?(left, right), do: left == right

  defp flip(:eq), do: :eq

  defp flip(:gt), do: :lt

  defp flip(:lt), do: :gt

  defp matches?(row, filter, opts, ranks) do
    Enum.all?(filter, &matches_predicate?(row, &1, opts, ranks))
  end

  defp matches_predicate?(row, {name, operator, operand}, opts, ranks) do
    ranks_for_key = Map.get(ranks, name)

    case resolve(operand, opts, ranks_for_key) do
      # The acting user is nobody, so a predicate asking about them is asking about nobody -
      # which no row answers, the way an actor-referencing statement is elided for a visitor
      # rather than run against a null.
      :no_actor -> false
      value -> satisfies?(operator, Map.fetch!(row, name), value, ranks_for_key)
    end
  end

  # The ranks a term's own predicates compare by, keyed by the attribute each names.
  defp predicate_ranks(term) do
    names = Enum.map(term.filter, fn {name, _operator, _operand} -> name end)

    enum_ranks(term.entity, names)
  end

  defp resolve({:actor}, opts, _ranks_for_key) do
    Keyword.get(opts, :actor_user_id) || :no_actor
  end

  defp resolve({:placeholder, name}, opts, ranks_for_key) do
    bindings = Keyword.get(opts, :bindings, %{})

    case Map.fetch(bindings, name) do
      :error ->
        raise ArgumentError, message: "missing value for placeholder #{inspect(name)}"

      {:ok, value} ->
        value
        |> validate_binding!(name)
        |> validate_declared_value!(name, ranks_for_key)
    end
  end

  defp resolve(operand, opts, ranks_for_key) when is_list(operand) do
    Enum.map(operand, &resolve(&1, opts, ranks_for_key))
  end

  defp resolve(operand, _opts, _ranks_for_key), do: operand

  # Nil is a value like any other to the equality family - an unset attribute is unequal to a
  # set one, and a list may name it - while an ordering line has no place to put one, so a
  # comparison passes over what is not there.
  defp satisfies?(:!=, value, operand, _ranks), do: not equal?(value, operand)

  defp satisfies?(:==, value, operand, _ranks), do: equal?(value, operand)

  defp satisfies?(:in, value, operands, _ranks), do: Enum.any?(operands, &equal?(value, &1))

  defp satisfies?(:not_in, value, operands, _ranks) do
    not Enum.any?(operands, &equal?(value, &1))
  end

  defp satisfies?(_operator, nil, _operand, _ranks), do: false

  defp satisfies?(:<, value, operand, ranks) do
    compare_ordering_values(value, operand, ranks) == :lt
  end

  defp satisfies?(:<=, value, operand, ranks) do
    compare_ordering_values(value, operand, ranks) in [:eq, :lt]
  end

  defp satisfies?(:>, value, operand, ranks) do
    compare_ordering_values(value, operand, ranks) == :gt
  end

  defp satisfies?(:>=, value, operand, ranks) do
    compare_ordering_values(value, operand, ranks) in [:eq, :gt]
  end

  defp sort(rows, order_by, entity_type) do
    names = Enum.map(order_by, fn {name, _direction} -> name end)
    ranks = enum_ranks(entity_type, names)

    Enum.sort(rows, &precedes?(&1, &2, order_by, ranks))
  end

  # Every key of the order is spent before two rows are called equal, and the last of them is
  # always the id, so no two rows ever are.
  defp precedes?(_left, _right, [], _ranks), do: false

  defp precedes?(left, right, [{name, direction} | rest], ranks) do
    left_value = Map.fetch!(left, name)
    right_value = Map.fetch!(right, name)

    case compare_keys(left_value, right_value, direction, Map.get(ranks, name)) do
      :eq -> precedes?(left, right, rest, ranks)
      :lt -> true
      :gt -> false
    end
  end

  # The reference field's atom is one the entity's own struct defines, so it is always there to
  # be found rather than invented here.
  defp reference_field(name), do: String.to_existing_atom("#{name}_id")

  defp relationship_kind(entity_type, name) do
    case Enum.find(entity_type.__relationships__(), fn {field, _target, _opts} ->
           field == name
         end) do
      {_field, [_target], _opts} -> :to_many
      _to_one -> :to_one
    end
  end

  defp table(database, entity_type) do
    database.rows
    |> Map.get(entity_type, %{})
    |> Map.values()
  end

  defp take(rows, nil), do: rows

  defp take(rows, limit), do: Enum.take(rows, limit)

  # The values the rank map holds, back in the order the entity declares them - the cold path of
  # a refusal, so the sort costs nothing anything else pays for.
  defp declared_values(ranks_for_key) do
    ranks_for_key
    |> Enum.sort_by(fn {_value, index} -> index end)
    |> Enum.map(fn {value, _index} -> value end)
  end

  # A binding on an enum attribute is one of the values that attribute declares, refused in the
  # words the database executor refuses it in - QueryRunner validates every binding against the
  # attribute before a statement is built, so an undeclared label never reaches Postgres on that
  # tier either. A list bound as a whole is left to the runner alone.
  defp validate_declared_value!(value, _name, nil), do: value

  defp validate_declared_value!(values, _name, _ranks_for_key) when is_list(values), do: values

  defp validate_declared_value!(value, name, ranks_for_key) do
    if Map.has_key?(ranks_for_key, value) do
      value
    else
      raise ArgumentError,
        message:
          "invalid value #{inspect(value)} for placeholder #{inspect(name)} - expected one of #{inspect(declared_values(ranks_for_key))}"
    end
  end

  # A binding carries no nil anywhere, which is what the database refuses it for - and identity
  # with the database covers what each REFUSES, not only what each answers. A predicate about the
  # rows that have no value is written as one, in the query, where the operator can be chosen to
  # suit. A LITERAL list may still name nil: it is part of a term rather than a value handed to
  # one, so it says what it means on its face.
  defp validate_binding!(nil, name) do
    raise ArgumentError,
      message:
        "nil value for placeholder #{inspect(name)} - use an explicit nil predicate instead"
  end

  defp validate_binding!(values, name) when is_list(values) do
    if Enum.any?(values, &is_nil/1) do
      raise ArgumentError,
        message:
          "nil element in the list for placeholder #{inspect(name)} - use an explicit nil predicate instead"
    end

    values
  end

  defp validate_binding!(value, _name), do: value
end
