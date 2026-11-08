defmodule Hologram.StateError do
  @moduledoc """
  Raised when a component's state is invalid.
  """

  defexception [:message]
end
