defmodule Hologram.Server.CookieStore do
  alias Hologram.Server.Cookie

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => Cookie.op() | String.t()},
          pending: %{String.t() => Cookie.op()}
        }
end
