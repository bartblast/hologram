defmodule Hologram.Operation do
  defstruct type: nil, target: nil, params: []

  @type t :: %__MODULE__{type: :action | :command, target: atom | nil, params: keyword}
end
