defmodule Hologram.Server.Metadata do
  alias Hologram.Runtime.CookieStore

  defstruct cookie_ops: %{}

  @type t :: %__MODULE__{
          cookie_ops: %{String.t() => CookieStore.op()}
        }
end
