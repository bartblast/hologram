defmodule Hologram.ActionResult do
  alias Hologram.Operation

  defstruct command: nil, context: nil, navigate: nil, state: nil

  @type t :: %__MODULE__{
          command: Operation.t(),
          context: %{atom => any} | %{{module, atom} => any},
          navigate: module | {module, keyword},
          state: %{atom => any}
        }
end
