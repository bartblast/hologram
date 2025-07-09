defmodule Hologram.Server.Metadata do
  alias Hologram.Server.Cookie

  defstruct cookie_ops: %{}

  @type t :: %__MODULE__{
          cookie_ops: %{String.t() => cookie_op}
        }

  @type cookie_op :: {:delete, pos_integer} | {:put, pos_integer, Cookie.t()}
end
