defmodule Hologram.Sync.Seed do
  @moduledoc false

  # The rows a page's own render resolved, gathered as it renders and handed to the client with
  # the page.
  #
  # What it buys: from the first client render, every `from_query` prop answers from the client's
  # own database rather than from a value the server passed down - no second evaluation path, no
  # swap when the stream finishes filling. The two executors agreeing is what makes that first
  # render match the HTML the server sent.
  #
  # Rows are spelled the way a frame spells them, so the client reads them through the same
  # ingest as everything else. What arrives this way is INSERT-ONLY there: a seed can be older
  # than what the client already holds - a page rendered at one moment can land after the stream
  # delivered a later change to the same row - and overwriting would put back a value nothing
  # would correct.
  #
  # Gathered in the process dictionary rather than threaded through the render: what a render
  # resolved is ambient to it, the way the acting user is, and the alternative is a new argument
  # on every render function. Both are request-scoped and neither outlives the response.

  alias Hologram.DB.Codec
  alias Hologram.Entity.NotIncluded
  alias Hologram.Sync.WireData

  @key {__MODULE__, :entities}

  @doc """
  Records the entities the given query result holds - the rows themselves and everything they
  embed, however deep.

  A result that is a count rather than rows holds no entity and records nothing.
  """
  @spec collect(any) :: :ok
  def collect(result) do
    collected =
      result
      |> entities()
      |> Enum.reduce(gathered(), &Map.put_new(&2, key(&1), &1))

    Process.put(@key, collected)

    :ok
  end

  @doc """
  Returns the rows gathered so far, grouped the way a frame groups them - by op, then by entity
  type - and clears what was gathered.

  Nothing gathered answers with an empty map rather than an empty put, since a page whose props
  read no rows has nothing to say rather than something empty to say.
  """
  @spec take() :: %{optional(:put_entity) => %{String.t() => list(map)}}
  def take do
    entities = Map.values(gathered())

    Process.delete(@key)

    if entities == [] do
      %{}
    else
      %{put_entity: group(entities)}
    end
  end

  defp entities(%NotIncluded{}), do: []

  defp entities(nil), do: []

  defp entities(results) when is_list(results), do: Enum.flat_map(results, &entities/1)

  defp entities(%entity_type{} = entity) do
    embedded =
      Enum.flat_map(entity_type.__relationships__(), fn {name, _target, _opts} ->
        entities(Map.fetch!(entity, name))
      end)

    [entity | embedded]
  end

  defp entities(_count), do: []

  defp gathered, do: Process.get(@key, %{})

  # Ordered by id within each type, so that one render's seed is spelled the same way twice -
  # what a map hands its values over in follows the hashes of the keys.
  defp group(entities) do
    entities
    |> Enum.group_by(&Codec.encode_enum_value(&1.__struct__))
    |> Map.new(fn {type_name, rows} ->
      {type_name,
       rows
       |> Enum.sort_by(& &1.id)
       |> Enum.map(&WireData.row/1)}
    end)
  end

  # One row can be reached from several props, and the same row twice is the same row - what
  # tells two apart is the pair of what they are and which one they are.
  defp key(%entity_type{id: id}), do: {entity_type, id}
end
