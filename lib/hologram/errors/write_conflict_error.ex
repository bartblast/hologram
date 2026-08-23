defmodule Hologram.WriteConflictError do
  @moduledoc """
  Raised by the raising variants of the write verbs when a write conflicts with what the
  database already holds - a value a unique attribute carries on another row, or a reference
  that still needs the row being deleted.

  The reason field holds what the plain variant would have returned under `{:error, ...}`.
  """

  defexception [:message, :reason]
end
