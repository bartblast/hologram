defmodule Hologram.Query.Window do
  @moduledoc false

  # What a query downloads, as opposed to what it answers. A client holds the rows its queries
  # could need rather than the ones they select right now, so changing a value re-runs the query
  # over what is already there instead of asking for more.

  @doc """
  Returns the window term of the given query term - the same query with the predicates that
  cannot say anything about the download taken out.

  A predicate comparing an attribute to a PARAM is dropped, whatever the operator: the value is
  unknown when the window is derived, so it bounds nothing, and the answer for every value it may
  take has to be in what arrives. What keeps that download finite is elsewhere - the model bounds
  an enum or a boolean by what it declares, and the read policy bounds a reference by the rows
  the actor may see, which is applied to the download in any case.

  A predicate comparing to a LITERAL stays: an app whose only query asks for todo projects is
  saying the others are never needed.

  Order, limit and offset are emptied rather than dropped. They shape what a query answers rather
  than what it downloads, so two queries reading the same rows in different orders share one
  window - but a window IS a query term and is run as one, so it keeps a term's shape and states
  that it asks for every row, in no order.

  KNOWN CONSEQUENCE, recorded rather than worked around: a query whose only bound is a param
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
      filter: Enum.reject(term.filter, &param_bound?/1),
      include: Map.new(term.include, fn {name, sub_term} -> {name, derive(sub_term)} end),
      limit: nil,
      offset: nil,
      order_by: []
    }
  end

  defp param?({:param, _name}), do: true

  defp param?(values) when is_list(values), do: Enum.any?(values, &param?/1)

  defp param?(_value), do: false

  defp param_bound?({_name, _operator, value}), do: param?(value)
end
