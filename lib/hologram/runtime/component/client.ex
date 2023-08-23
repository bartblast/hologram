defmodule Hologram.Component.Client do
  alias Hologram.Operation

  defstruct context: %{}, next_command: nil, state: %{}

  @type t :: %__MODULE__{
          context: %{atom => any} | %{{module, atom} => any},
          next_command: Operation.t() | nil,
          state: %{atom => any}
        }
end
