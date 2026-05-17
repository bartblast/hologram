defmodule Hologram.Server.Broadcast do
  @moduledoc """
  A single broadcast entry queued on `Hologram.Server`'s `broadcasts` field.

  `except` lists identities (`{:instance, id}`, `{:session, id}`, `{:user, id}`)
  that should not receive the broadcast. Empty list means no exclusions.
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
