defmodule Hologram.Conn do
  @type t :: %__MODULE__{params: map, session: map}

  defstruct params: %{}, session: %{}
end
