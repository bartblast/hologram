defmodule Hologram.Server.Metadata do
  alias Hologram.Server.Cookie

  defstruct cookie_ops: %{}

  @type t :: %__MODULE__{
          cookie_ops: %{String.t() => Cookie.op()}
        }
end
