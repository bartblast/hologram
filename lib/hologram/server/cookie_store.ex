defmodule Hologram.Server.CookieStore do
  alias Hologram.Server.Metadata

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => Metadata.cookie_op() | String.t()},
          pending: %{String.t() => Metadata.cookie_op()}
        }
end
