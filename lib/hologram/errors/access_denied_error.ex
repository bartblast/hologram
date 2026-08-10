defmodule Hologram.AccessDeniedError do
  @moduledoc """
  Raised when the acting user may not perform the attempted action.
  """

  defexception [:message]
end
