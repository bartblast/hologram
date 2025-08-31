defmodule Hologram.Server.Metadata do
  @moduledoc false

  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.Session

  defstruct cookie_ops: %{}, session_ops: %{}

  @type t :: %__MODULE__{
          cookie_ops: %{String.t() => Cookie.op()},
          session_ops: %{String.t() => Session.op()}
        }
end
