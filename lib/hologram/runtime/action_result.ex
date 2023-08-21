defmodule Hologram.ActionResult do
  alias Hologram.Operation

  defstruct command: nil, context: %{}, navigate: nil, state: %{}

  @type t :: %__MODULE__{
          command: Operation.t(),
          context: %{atom => any} | %{{module, atom} => any},
          navigate: module | {module, keyword} | nil,
          state: %{atom => any}
        }
end
