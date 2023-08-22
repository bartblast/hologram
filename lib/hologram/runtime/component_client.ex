defmodule Hologram.ComponentClient do
  alias Hologram.Operation

  defstruct context: %{}, next_command: nil, state: %{}

  @type t :: %__MODULE__{
          context: %{atom => any} | %{{module, atom} => any},
          next_command: Operation.t(),
          state: %{atom => any}
        }
end
