defmodule Hologram.Runtime.CookieStore do
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.PlugConnUtils

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => Cookie.op() | String.t()},
          pending: %{String.t() => Cookie.op()}
        }

  def from(%Plug.Conn{} = conn) do
    %__MODULE__{
      persisted: PlugConnUtils.extract_cookies(conn)
    }
  end
end
