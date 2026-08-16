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
  alias Hologram.Sync.Frame

  @doc """
  Decides what a connection carrying the given greeting gets.

  Answers `{:sync, page, cursor}` when the client can be served, `{:reload, reason}` when its
  bundle disagrees with this build, and `:no_sync` when there is nothing to serve - which is
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
  """
  @spec check(map) :: {:sync, module, String.t() | nil} | {:reload, atom} | :no_sync
  def check(greeting) do
    case greeting do
      %{model_hash: model_hash, page: page, protocol_version: protocol_version} ->
        check_greeting(page, protocol_version, model_hash, greeting[:cursor])

      _no_greeting ->
        :no_sync
    end
  end

  defp check_greeting(page, protocol_version, model_hash, cursor) do
    cond do
      not Model.exists?() -> :no_sync
      protocol_version != Frame.protocol_version() -> {:reload, :protocol_version}
      model_hash != Model.hash() -> {:reload, :model_hash}
      true -> {:sync, page, cursor}
    end
  end
end
