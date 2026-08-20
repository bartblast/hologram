defmodule Hologram.Query.Window do
  @moduledoc false

  # What a query downloads, as opposed to what it answers. A client holds the rows its queries
  # could need rather than the ones they select right now, so changing a value re-runs the query
  # over what is already there instead of asking for more.

  @doc """
  Returns the window term of the given query term - the same query with the predicates that
  cannot say anything about the download taken out.

  A predicate is dropped when a PARAM stands on either side of it - as the value, whatever the
  operator, or as the attribute being compared. Both are unknown when the window is derived, so
  the predicate bounds nothing, and the answer for every value it may take has to be in what
  arrives. What keeps that download finite is elsewhere - the model bounds an enum or a boolean by
  what it declares, and the read policy bounds a reference by the rows the actor may see, which is
  applied to the download in any case.

  A predicate comparing to a LITERAL stays: an app whose only query asks for todo projects is
  saying the others are never needed.

  Order, limit and offset are emptied rather than dropped. They shape what a query answers rather
  than what it downloads, so two queries reading the same rows in different orders share one
  window - but a window IS a query term and is run as one, so it keeps a term's shape and states
  that it asks for every row, in no order.

  KNOWN CONSEQUENCE, recorded rather than worked around: a query whose only bound is a placeholder
  downloads everything the policy admits. A thirty-day message window written as
  `created_at: {:>, ^cutoff}` downloads the channel's whole history, because a cutoff computed
  per render says nothing at compile time. Bounding it needs the thirty days written into the
  query itself - a relative bound the compiler can read and the server evaluates per run - which
  the filter surface does not offer yet.
  """
  @spec derive(%{atom => any}) :: %{atom => any}
  def derive(term) do
    %{
      cardinality: :set,
      entity: term.entity,
      filter: Enum.reject(term.filter, &placeholder_bound?/1),
      include: Map.new(term.include, fn {name, sub_term} -> {name, derive(sub_term)} end),
      limit: nil,
      offset: nil,
      order_by: []
    }
  end

  defp placeholder?({:placeholder, _name}), do: true

  defp placeholder?(values) when is_list(values), do: Enum.any?(values, &placeholder?/1)

  defp placeholder?(_value), do: false

  defp placeholder_bound?({name, _operator, value}), do: placeholder?(name) or placeholder?(value)
end
