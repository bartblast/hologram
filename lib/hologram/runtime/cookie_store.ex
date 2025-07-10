defmodule Hologram.Runtime.CookieStore do
  alias Hologram.Runtime.Cookie

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => Cookie.op() | String.t()},
          pending: %{String.t() => Cookie.op()}
        }
end
