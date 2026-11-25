defmodule Hologram.Sync.Sessions do
  @moduledoc false

  # The sync sessions running on this node, each with the user it serves - what every batch of
  # changes is judged for. A session joins when it starts and leaves by dying, so the list needs no
  # bookkeeping of its own: a session that crashes takes its entry with it.
  #
  # Keyed by the session's own process rather than all under one key: a registry clears a process's
  # entries by its key, and one key shared by every session makes each exit scan all of them - tens
  # of thousands of sessions leaving at once, as on a deploy, take seconds to be cleared.
  #
  # Registering links the session to the registry, so the registry being replaced - a restart of
  # the sync unit - stops every session in it that doesn't trap exits (see
  # `Hologram.Sync.Supervisor`).

  alias Hologram.Auth

  @registry Hologram.Sync.SessionRegistry

  @doc """
  Returns the child spec of the registry the sessions are kept in.
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @doc """
  Cuts every session on this node with the given reason. Each one stops once it has read what was
  queued ahead of the cut, and its client comes back through the doors.
  """
  @spec cut_all(term) :: :ok
  def cut_all(reason) do
    Enum.each(list(), fn {session, _user_id} -> send(session, {:cut, reason}) end)
  end

  @doc """
  Returns every session on this node, each with the user it serves: an id in the spelling
  Hologram generates, or nil for an anonymous one - and for a user id in any other spelling, which
  names no user entity (see `Hologram.Auth.canonical_id/1`).
  """
  @spec list() :: list({pid, String.t() | nil})
  def list do
    Registry.select(@registry, [{{:"$1", :_, :"$2"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Adds the calling process to the sessions on this node, serving the given user - nil for an
  anonymous one. A process registers once: a second registration raises, since it would have every
  batch judged and sent to it twice.
  """
  @spec register(any) :: :ok
  def register(user_id) do
    {:ok, _owner} = Registry.register(@registry, self(), Auth.canonical_id(user_id))

    :ok
  end

  @doc """
  Returns the name of the registry the sessions are kept in.
  """
  @spec registry() :: atom
  def registry, do: @registry
end
