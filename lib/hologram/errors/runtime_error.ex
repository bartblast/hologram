defmodule Hologram.RuntimeError do
  @moduledoc """
  Raised when there is framework runtime error.
  """

  defexception [:message]
end
