defmodule HologramSyncTests.Consistency.Checks do
  @moduledoc false

  # The consistency checks. The first: once writes stop, a client holds exactly what its user may
  # read - every row, with its current fields and sets, and nothing more.

  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.Model

  @typedoc """
  One way a client's store differs from what it should hold.
  """
  @type difference ::
          :incomplete
          | {:missing, module, String.t(), map}
          | {:extra, module, String.t(), map}
          | {:fields, module, String.t(), expected :: map, held :: map}
          | {:set, module, String.t(), String.t(), expected :: list, held :: list}

  @doc """
  Polls until the given client says it holds everything and its store equals what its user may
  read in the tables' current state, for at most the given milliseconds. Answers the differences
  left when the time runs out, led by `:incomplete` when the client was still waiting to be told
  it holds everything.
  """
  @spec await_converged(pid, String.t() | nil, non_neg_integer) ::
          :ok | {:error, list(difference)}
  def await_converged(client, user_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    poll_converged(client, user_id, deadline)
  end

  @doc """
  Returns how the given store differs from the given expected rows, both in the shape
  `Model.expected/2` answers, sorted by type and id.
  """
  @spec diff(map, map) :: list(difference)
  def diff(store, expected) do
    differences =
      Enum.flat_map(Model.types(), fn type ->
        held = Map.get(store, type, %{})
        wanted = Map.get(expected, type, %{})

        (Map.keys(held) ++ Map.keys(wanted))
        |> Enum.uniq()
        |> Enum.flat_map(&row_diff(type, &1, Map.get(wanted, &1), Map.get(held, &1)))
      end)

    Enum.sort_by(differences, fn difference -> {elem(difference, 1), elem(difference, 2)} end)
  end

  defp poll_converged(client, user_id, deadline) do
    store_differences = diff(Client.store(client), Model.expected(Model.snapshot(), user_id))

    differences =
      if Client.complete?(client), do: store_differences, else: [:incomplete | store_differences]

    cond do
      differences == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, differences}

      true ->
        Process.sleep(50)
        poll_converged(client, user_id, deadline)
    end
  end

  defp row_diff(_type, _id, nil, nil), do: []

  defp row_diff(type, id, wanted, nil), do: [{:missing, type, id, wanted}]

  defp row_diff(type, id, nil, held), do: [{:extra, type, id, held}]

  defp row_diff(type, id, wanted, held) do
    set_names =
      type
      |> Model.sets()
      |> Map.keys()

    {wanted_sets, wanted_fields} = Map.split(wanted, set_names)
    {held_sets, held_fields} = Map.split(held, set_names)

    fields =
      if wanted_fields == held_fields,
        do: [],
        else: [{:fields, type, id, wanted_fields, held_fields}]

    sets =
      for name <- set_names,
          Map.get(wanted_sets, name) != Map.get(held_sets, name),
          do: {:set, type, id, name, Map.get(wanted_sets, name), Map.get(held_sets, name)}

    fields ++ sets
  end
end
