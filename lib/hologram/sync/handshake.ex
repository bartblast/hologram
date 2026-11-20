defmodule Hologram.Sync.Handshake do
  @moduledoc false

  # What a client says when it arrives, and whether it can be served. Not to be confused with
  # `Hologram.Realtime.Handshake`, which stashes what an SSE connection redeems - this decides
  # whether that connection also syncs.
  #
  # A client's bundle was built against one model and speaks one protocol version. A hash says
  # which model, never which is newer: order lives in the migration table, where history is. A
  # client of another model is served when the table places its hash in this release's history and
  # every change since can be given back by renaming (see `Hologram.Sync.Lens`) - through a lens,
  # and only the entity types its bundle names. Any other is told to reload.

  alias Hologram.DB.QueryCache
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.StaleModelError
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Lens

  @doc """
  Decides what a connection carrying the given greeting gets.

  Answers `{:sync, page, cursor, policy_hash, stale_rules?, serving}` when the client can be served,
  `{:reload, reason}` when its bundle disagrees with this build in a way it can't be served across,
  and `:no_sync` when there is nothing to serve - which is
  either a client that said nothing about sync (what one built before any of this existed looks
  like) or a build with no data model at all. Both keep the realtime stream they already have.

  An app declaring no entity types has no database - the application tree gates the whole data
  layer on exactly that - so nothing about it can be synced and no client of it may be answered
  as though something could. Asked anyway, this says no rather than reaching for a pool that was
  never started.

  The page is the client's own claim and is taken at face value: what it names decides only which
  windows fill first, never what it may see of them, which every row is checked against
  separately.

  The cursor passes through unread, and is nil for a client arriving for the first time. Whether
  the place it names can still be reached is a question about the log, and this is about the
  bundle.

  `policy_hash` is the hash of the rules this build enforces (see `Hologram.Policy.hash/0`), read
  once here so that whatever the client is served is judged by the rules it was compared with.
  `stale_rules?` is whether the bundle was built with rules other than those - a deploy that
  changed only policies leaves the model hash as it was, so a client is served with them either
  way, and told the current ones beside its rows. A greeting naming no rules - a test client's,
  every bundle names them - is taken as current. Never for a client of another model: the current
  rules name what the current model calls things, and would be judged over rows in the client's
  shape. It keeps its bundle's rules, which decide only what its pages offer.

  `serving` says how: `%{lens: nil, types: nil}` for a client of this model, sent the entity types
  this build syncs as they are, and for one of another `%{lens: lens, model_hash: hash, types:
  types}`, with the lens it is served through, the hash of the model the lens translates from and
  the current entity types of the ones its greeting names. Every one has
  to be a type this build syncs: one only an older build's code read has no rows coming, so a client
  naming it is told to reload, and so is one whose greeting says nothing of its types - a bundle
  built before bundles named them, or one whose list was too long to carry.

  Answers `:held` for a greeting arriving while the data model is under a hold (see
  `Hologram.Entity.Model.hold/0`): neither the model nor its hash can be read until it is released,
  so whether the client can be served is not known yet.
  """
  @spec check(map) ::
          {:sync, module, String.t() | nil, String.t(), boolean,
           %{optional(:model_hash) => String.t(), lens: Lens.t() | nil, types: list(module) | nil}}
          | {:reload, atom}
          | :held
          | :no_sync
  def check(greeting) do
    case greeting do
      %{model_hash: model_hash, page: page, protocol_version: protocol_version} ->
        check_greeting(greeting, page, protocol_version, model_hash)

      _no_greeting ->
        :no_sync
    end
  end

  # Every answer but the protocol's reads the data model, and a hold can begin between any two of
  # those reads, so meeting one anywhere is the same answer as arriving under it.
  defp check_greeting(greeting, page, protocol_version, model_hash) do
    cond do
      not Model.exists?() -> :no_sync
      protocol_version != Frame.protocol_version() -> {:reload, :protocol_version}
      true -> sync_model(greeting, page, model_hash, Model.hash())
    end
  rescue
    StaleModelError -> :held
  end

  defp stale_rules?(nil, _policy_hash), do: false

  defp stale_rules?(greeting_policy_hash, policy_hash), do: greeting_policy_hash != policy_hash

  defp sync(greeting, page) do
    policy_hash = Policy.hash()

    {:sync, page, greeting[:cursor], policy_hash,
     stale_rules?(greeting[:policy_hash], policy_hash), %{lens: nil, types: nil}}
  end

  defp sync_model(greeting, page, current_hash, current_hash), do: sync(greeting, page)

  defp sync_model(greeting, page, model_hash, _current_hash),
    do: sync_old(greeting, page, model_hash)

  # The lens is of the model running when it was built, which a live reload can change before the
  # session starts - so the serving names it, and the start checks it still runs (see
  # `Hologram.Realtime.SSE.read_sync_start/6`).
  defp sync_old(greeting, page, model_hash) do
    with labels when is_list(labels) <- greeting[:synced_types],
         {:ok, lens} <- Lens.for_hash(model_hash),
         {:ok, types} <- served_types(lens, labels) do
      serving = %{lens: lens, model_hash: lens.model_hash, types: types}

      {:sync, page, greeting[:cursor], Policy.hash(), false, serving}
    else
      _unservable -> {:reload, :model_hash}
    end
  end

  defp served_types(lens, labels) do
    synced = MapSet.new(QueryCache.synced_types())
    types = Enum.map(labels, &Lens.current_type(lens, &1))

    if Enum.all?(types, &MapSet.member?(synced, &1)) do
      {:ok, Enum.uniq(types)}
    else
      :error
    end
  end
end
