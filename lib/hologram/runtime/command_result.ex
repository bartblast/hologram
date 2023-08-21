defmodule Hologram.CommandResult do
  alias Hologram.Operation

  defstruct action: nil, cookies: %{}, navigate: nil, session: %{}

  @type t :: %__MODULE__{
          action: Operation.t(),
          cookies: %{atom => any},
          navigate: module | {module, keyword} | nil,
          session: %{atom => any}
        }
end
