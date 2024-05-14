defmodule Hologram.Server do
  alias Hologram.Component.Action

  defstruct cookies: %{}, next_action: nil, session: %{}

  @type t :: %__MODULE__{
          cookies: %{atom => any},
          next_action: Action.t() | nil,
          session: %{atom => any}
        }
end
