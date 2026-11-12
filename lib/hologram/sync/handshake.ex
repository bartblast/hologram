defmodule Hologram.Sync.Handshake do
  @moduledoc false

  # What a client says when it arrives, and whether it can be served. Not to be confused with
  # `Hologram.Realtime.Handshake`, which stashes what an SSE connection redeems - this decides
  # whether that connection also syncs.
  #
  # A client's bundle was built against one model and speaks one protocol version. Both are
  # compared for equality and nothing else: a hash says which model, never which is newer, and
  # order lives in the migration table where history is. Serving a client whose bundle disagrees
  # is what lenses will make possible - until they exist, the answer is to reload.

  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.Frame

  @doc """
  Decides what a connection carrying the given greeting gets.

  Answers `{:sync, page, cursor, policy_hash, stale_rules?}` when the client can be served,
  `{:reload, reason}` when its bundle disagrees with this build, and `:no_sync` when there is
  nothing to serve - which is
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
  way, and told the current ones beside its rows. A bundle that checks no permissions names no
  rules, and has none to fall behind.

  Answers `:held` for a greeting arriving while the data model is under a hold (see
  `Hologram.Entity.Model.hold/0`): neither the model nor its hash can be read until it is released,
  so whether the client can be served is not known yet.
  """
  @spec check(map) ::
          {:sync, module, String.t() | nil, String.t(), boolean}
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

  defp check_greeting(greeting, page, protocol_version, model_hash) do
    cond do
      Model.held?() -> :held
      not Model.exists?() -> :no_sync
      protocol_version != Frame.protocol_version() -> {:reload, :protocol_version}
      model_hash != Model.hash() -> {:reload, :model_hash}
      true -> sync(greeting, page)
    end
  end

  defp stale_rules?(nil, _policy_hash), do: false

  defp stale_rules?(greeting_policy_hash, policy_hash), do: greeting_policy_hash != policy_hash

  defp sync(greeting, page) do
    policy_hash = Policy.hash()

    {:sync, page, greeting[:cursor], policy_hash,
     stale_rules?(greeting[:policy_hash], policy_hash)}
  end
end
