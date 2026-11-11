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
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Sync.Frame

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
  Records the given count under the key naming the query prop or derived field that answered it.

  A counting query answers with a number and no rows, so nothing about it can be re-derived from
  the rows a page carries - the client is told the number itself, and holds it until its own database is
  complete enough to count.

  The key names the component, the prop or field, and the arguments its function was called with,
  which is what tells two instances of one component apart. The arguments are spelled the same way on
  both tiers, which `inspect/1` alone doesn't do for a struct: an entity row by its type and id, the
  only parts both tiers are sure to hold alike, a list, a tuple and a map by their items, a map's
  entries and a struct's fields sorted, and anything else by `inspect/1`, in full.
  """
  @spec collect_count(module, atom, list, integer) :: :ok
  def collect_count(module, name, args, count) do
    collected = Map.put(gathered_counts(), count_key(module, name, args), count)

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

  A row reached more than once - in several places of one result, or by several results - is
  recorded once, carrying every relationship any of its copies included.

  A result that is a count rather than rows holds no entity and records nothing.
  """
  @spec collect(any) :: :ok
  def collect(result) do
    collected =
      result
      |> entities()
      |> Enum.reduce(gathered(), fn entity, acc ->
        Map.update(acc, key(entity), entity, &Entity.merge_copies(&1, entity))
      end)

    Process.put(@key, collected)

    :ok
  end

  @doc """
  Returns the rows gathered so far, grouped the way a frame groups them - by op, then by entity
  type - and clears what was gathered.

  Nothing gathered answers with an empty map rather than an empty put, since a page whose props
  read no rows has nothing to say rather than something empty to say. Each row carries the server's
  verdicts for the given user, the render's, as a frame's put does (see
  `Hologram.Sync.Frame.row_verdicts/2`).
  """
  @spec take(String.t() | nil) :: %{optional(:put_entity) => %{String.t() => list(map)}}
  def take(actor_user_id) do
    entities = Map.values(gathered())

    Process.delete(@key)

    if entities == [] do
      %{}
    else
      %{put_entity: group(entities, actor_user_id)}
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

  # WARNING: must match the client's DataLayer.#carriedCount (data_layer.mjs).
  defp count_key(module, name, args) do
    "#{inspect(module)}/#{name}/#{Enum.map_join(args, ",", &spell_key_part/1)}"
  end

  defp entities(%NotIncluded{}), do: []

  defp entities(nil), do: []

  defp entities(results) when is_list(results), do: Enum.flat_map(results, &entities/1)

  defp entities(%entity_type{} = entity) do
    embedded =
      entity_type
      |> Entity.includable_names()
      |> Enum.flat_map(&entities(Map.fetch!(entity, &1)))

    [entity | embedded]
  end

  defp entities(_count), do: []

  defp gathered, do: Process.get(@key, %{})

  defp gathered_counts, do: Process.get(@counts_key, %{})

  # Ordered by id within each type, so that one render's rows are spelled the same way twice -
  # what a map hands its values over in follows the hashes of the keys.
  defp group(entities, actor_user_id) do
    entities
    |> Enum.group_by(&Codec.encode_enum_value(&1.__struct__))
    |> Map.new(fn {type_name, rows} ->
      {type_name,
       rows
       |> Enum.sort_by(& &1.id)
       |> Enum.map(&Frame.put_entity(&1, Frame.row_verdicts(actor_user_id, &1)).data)}
    end)
  end

  # One row can be reached from several props, and the same row twice is the same row - what
  # tells two apart is the pair of what they are and which one they are.
  defp key(%entity_type{id: id}), do: {entity_type, id}

  defp spell_entity_id(id) when is_binary(id), do: id

  defp spell_entity_id(id), do: spell_key_part(id)

  # A row is told apart by the metadata every entity struct carries, rather than by its type, so a
  # row of a type the client's model doesn't bake is spelled the same way there.
  #
  # WARNING: must match the client's DataLayer.#spellKeyPart (data_layer.mjs).
  defp spell_key_part(%module{__meta__: %Metadata{}} = term),
    do: "#{inspect(module)}##{spell_entity_id(term.id)}"

  defp spell_key_part(%module{} = term) do
    fields =
      term
      |> Map.from_struct()
      |> Enum.sort_by(fn {key, _value} -> Atom.to_string(key) end)
      |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{spell_key_part(value)}" end)

    "%#{inspect(module)}{#{fields}}"
  end

  defp spell_key_part(term) when is_map(term) do
    entries =
      term
      |> Enum.map(fn {key, value} -> {spell_key_part(key), spell_key_part(value)} end)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {key, value} -> "#{key} => #{value}" end)

    "%{#{entries}}"
  end

  defp spell_key_part(term) when is_list(term) do
    items =
      term
      |> spell_list_items()
      |> Enum.join(", ")

    "[#{items}]"
  end

  defp spell_key_part(term) when is_tuple(term) do
    items =
      term
      |> Tuple.to_list()
      |> Enum.map_join(", ", &spell_key_part/1)

    "{#{items}}"
  end

  # The client's inspect spells some floats unlike Elixir's, so a float is spelled by its bits.
  defp spell_key_part(term) when is_float(term) do
    <<bits::binary-size(8)>> = <<term::float-64>>

    "float:#{Base.encode16(bits, case: :lower)}"
  end

  defp spell_key_part(term), do: inspect(term, limit: :infinity, printable_limit: :infinity)

  # Walked rather than mapped, so an improper list's tail is spelled after a bar, as inspect does.
  defp spell_list_items([]), do: []

  defp spell_list_items([item | rest]) when is_list(rest),
    do: [spell_key_part(item) | spell_list_items(rest)]

  defp spell_list_items([item | tail]), do: ["#{spell_key_part(item)} | #{spell_key_part(tail)}"]
end
