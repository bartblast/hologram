defmodule Hologram.ComponentServer do
  alias Hologram.Operation

  defstruct cookies: %{}, next_action: nil, session: %{}

  @type t :: %__MODULE__{
          cookies: %{atom => any},
          next_action: Operation.t(),
          session: %{atom => any}
        }
end
