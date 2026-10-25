defmodule Hologram.Query.Window do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Query.Stage

  # What a query downloads, as opposed to what it answers. A client holds the rows its queries
  # could need rather than the ones they select right now, so changing a value re-runs the query
  # over what is already there instead of asking for more.

  @doc """
  Returns the window term of the given query term - the same query with the predicates that
  cannot say anything about the download taken out.

  A predicate is dropped when a PLACEHOLDER stands on either side of it - as the value, whatever the
  operator, or as the attribute being compared. Both are unknown when the window is derived, so
  the predicate bounds nothing, and the answer for every value it may take has to be in what
  arrives. What keeps that download finite is elsewhere - the model bounds an enum or a boolean by
  what it declares, and the read policy bounds a reference by the rows the actor may see, which is
  applied to the download in any case.

  A predicate comparing to a LITERAL stays: an app whose only query asks for todo projects is
  saying the others are never needed. So does one comparing two ATTRIBUTES of the row
  (`end_date < start_date`) - it says something about the row whatever value anything takes - and
  one reading a PATH, by the same rule: `channel.archived == false` keeps the messages of
  unarchived channels.

  A PATH reads rows the query does not return, and the client answers the query over what it
  holds, so every path the filter names - kept or dropped, on either side of a comparison, inside
  alternatives - has its relationships embedded in the window as to-one includes, merged with the
  query's own. The related rows arrive with the window and are kept current with it, and a change
  to one reaches the window the way a change to an included row does.

  A DISJUNCTION cannot drop a predicate the same way. Dropping a conjunct widens what arrives,
  which is safe - dropping an alternative narrows it, and `status == :todo or owner_id == ^user_id`
  would then download only the todo rows, while the query also answers for a user's own rows in
  every other status. So each alternative is narrowed to its literal predicates and the disjunction
  stays, unless an alternative loses every predicate: that alternative admits every row for some
  value of its placeholders, so the disjunction bounds nothing and is dropped whole, the clauses
  beside it staying. A nested disjunction follows the same rule from the inside out. Narrowing
  can move an alternative among the others, so the filter is put back in canonical order - two
  queries differing only in a pinned alternative must name one window.

  Order, limit and offset are emptied rather than dropped. They shape what a query answers rather
  than what it downloads, so two queries reading the same rows in different orders share one
  window - but a window IS a query term and is run as one, so it keeps a term's shape and states
  that it asks for every row, in no order.

  KNOWN CONSEQUENCE, recorded rather than worked around: a query whose only bound is a placeholder
  downloads everything the policy admits. A thirty-day message window written as
  `created_at > ^cutoff` downloads the channel's whole history, because a cutoff computed
  per render says nothing at compile time. Bounding it needs the thirty days written into the
  query itself - a relative bound the compiler can read and the server evaluates per run - which
  the filter surface does not offer yet.
  """
  @spec derive(Query.t()) :: Query.t()
  def derive(term) do
    filter =
      term.filter
      |> window_clauses()
      |> Stage.normalized_filter()

    include =
      term.include
      |> Map.new(fn {name, sub_term} -> {name, derive(sub_term)} end)
      |> put_path_includes(term)

    %Query{entity: term.entity, filter: filter, include: include}
  end

  defp placeholder?({:placeholder, _name}), do: true

  defp placeholder?(values) when is_list(values), do: Enum.any?(values, &placeholder?/1)

  defp placeholder?(_value), do: false

  # A path holds names only, never a placeholder, so only its value can bound nothing.
  defp placeholder_bound?({path, _operator, value}) when is_list(path), do: placeholder?(value)

  defp placeholder_bound?({name, _operator, value}), do: placeholder?(name) or placeholder?(value)

  # A to-one include carries no clauses, so a path's relationship joins one the window already
  # has by adding what it includes.
  defp put_path_include(include, _entity_type, []), do: include

  defp put_path_include(include, entity_type, [relationship_name | later_names]) do
    target_type = Entity.relationship_target(entity_type, relationship_name)
    included = Map.get(include, relationship_name, %Query{entity: target_type})
    nested = put_path_include(included.include, target_type, later_names)

    Map.put(include, relationship_name, %{included | include: nested})
  end

  defp put_path_includes(include, term) do
    term.filter
    |> Stage.predicate_references()
    |> Enum.reduce(include, fn {relationship_names, _name}, acc ->
      put_path_include(acc, term.entity, relationship_names)
    end)
  end

  defp window_clause({:or, alternatives}) do
    narrowed = Enum.map(alternatives, &window_clauses/1)

    if Enum.any?(narrowed, &(&1 == [])) do
      []
    else
      [{:or, narrowed}]
    end
  end

  defp window_clause(triple) do
    if placeholder_bound?(triple), do: [], else: [triple]
  end

  defp window_clauses(clauses), do: Enum.flat_map(clauses, &window_clause/1)
end
