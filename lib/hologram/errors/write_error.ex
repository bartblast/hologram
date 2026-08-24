defmodule Hologram.WriteError do
  @moduledoc """
  Raised by the raising variants of the write verbs (`Hologram.DB.create!/1`,
  `Hologram.DB.update!/3`, `Hologram.DB.delete!/2`) when the write is refused.

  The reason field holds what the plain variant would have returned under `{:error, ...}`.
  """

  defexception [:message, :reason]
end
