defmodule Hologram.PropError do
  @moduledoc """
  Raised when a component prop is invalid.
  """

  defexception [:message]
end
