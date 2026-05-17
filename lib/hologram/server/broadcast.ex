defmodule Hologram.Server.Broadcast do
  @moduledoc """
  Represents a single broadcast queued on `server.broadcasts` by `put_broadcast`
  or `put_broadcast_except`. Flushed by the framework after the handler returns
  successfully.

  `except` is the list of identities the dev explicitly excluded from delivery
  (`{:instance, id}`, `{:session, id}`, or `{:user, id}` tuples). Empty list
  for entries queued via `put_broadcast`. `put_broadcast_except` accepts a
  single identity tuple or a list; the mutator wraps a single tuple into a
  one-element list so storage is uniformly a list.
  """

  @type identity ::
          {:instance, String.t()} | {:session, String.t()} | {:user, integer | String.t() | atom}

  @enforce_keys [:channel, :cid, :action_name]
  defstruct [:channel, :cid, :action_name, params: %{}, except: []]

  @type t :: %__MODULE__{
          channel: atom | tuple,
          cid: String.t(),
          action_name: atom,
          params: map,
          except: [identity]
        }
end
