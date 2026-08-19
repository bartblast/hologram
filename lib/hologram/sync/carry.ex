defmodule Hologram.Sync.Carry do
  @moduledoc false

  # What a page's own render resolved - its rows, and the counts nothing but a number came back
  # for - gathered as it renders and handed to the client with the page.
  #
  # What it buys: from the first client render, every `from_query` prop answers from the client's
  # own database rather than from a value the server passed down - no second evaluation path, no
  # swap when the stream finishes filling. The two executors agreeing is what makes that first
  # render match the HTML the server sent.
  #
  # Rows are spelled the way a frame spells them, so the client reads them through the same
  # ingest as everything else. What arrives this way is applied INSERT-ONLY there: what a page
  # carries can be older than what the client already holds - a page rendered at one moment can
  # land after the stream delivered a later change to the same row - and overwriting would put
  # back a value nothing would correct.
  #
  # Gathered in the process dictionary rather than threaded through the render: what a render
  # resolved is ambient to it, the way the acting user is, and the alternative is a new argument
  # on every render function. Both are request-scoped and neither outlives the response.

  alias Hologram.DB.Codec
  alias Hologram.Entity.NotIncluded
  alias Hologram.Sync.WireData

  @key {__MODULE__, :entities}
  @counts_key {__MODULE__, :counts}
  @grant_scopes_key {__MODULE__, :grant_scopes}

  @doc """
  Clears what a previous render gathered and returns :ok.

  A render ends by taking what it gathered, so this is what covers the render that does not end -
  one that raises leaves its rows behind, and the process serving the next request would hand
  them to a page they never belonged to.
  """
  @spec start() :: :ok
  def start do
    Process.delete(@key)
    Process.delete(@counts_key)

    # Armed rather than cleared: a permission check outside a render finds no set here and
    # records nothing, which is what keeps the trusted paths (commands, mix tasks, IEx) free of
    # this entirely.
    Process.put(@grant_scopes_key, MapSet.new())

    :ok
  end

  @doc """
  Records the given count under the key naming the query prop that answered it.

  A counting query answers with a number and no rows, so nothing about it can be re-derived from
  the rows a page carries - the client is told the number itself, and holds it until its own database is
  complete enough to count.

  The key names the component, the prop, and the arguments the builder was called with, which is
  what tells two instances of one component apart - `inspect/1` spells the arguments, being the
  spelling both tiers already agree on.
  """
  @spec collect_count(module, atom, list, integer) :: :ok
  def collect_count(module, prop_name, args, count) do
    collected = Map.put(gathered_counts(), count_key(module, prop_name, args), count)

    Process.put(@counts_key, collected)

    :ok
  end

  @doc """
  Records that a permission check asked the grant store about the given user and scope, and
  returns :ok. Recording only happens while a render is gathering - outside one this is a no-op,
  so the trusted paths that check permissions without rendering pay nothing.

  A check asks whether a grant EXISTS - it reads no rows, so there is nothing for the entity
  collector to gather. What is kept is the question, which is what the rows answering it are
  looked up by when the render ends.
  """
  @spec record_grant_scope(String.t() | nil, tuple | atom) :: :ok
  def record_grant_scope(user_id, scope) do
    case Process.get(@grant_scopes_key) do
      nil ->
        :ok

      scopes ->
        Process.put(@grant_scopes_key, MapSet.put(scopes, {user_id, scope}))

        :ok
    end
  end

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

  @doc """
  Returns the counts gathered so far, keyed by query prop, and clears what was gathered.
  """
  @spec take_counts() :: %{String.t() => integer}
  def take_counts do
    counts = gathered_counts()

    Process.delete(@counts_key)

    counts
  end

  @doc """
  Returns the {user id, scope} pairs the render's permission checks asked about, and clears them.
  """
  @spec take_grant_scopes() :: MapSet.t({String.t() | nil, tuple | atom})
  def take_grant_scopes do
    scopes = Process.get(@grant_scopes_key, MapSet.new())

    Process.delete(@grant_scopes_key)

    scopes
  end

  defp count_key(module, prop_name, args) do
    "#{inspect(module)}/#{prop_name}/#{Enum.map_join(args, ",", &inspect/1)}"
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

  defp gathered_counts, do: Process.get(@counts_key, %{})

  # Ordered by id within each type, so that one render's rows are spelled the same way twice -
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
