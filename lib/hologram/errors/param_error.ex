defmodule Hologram.ParamError do
  @moduledoc """
  Raised when a page param is invalid.
  """

  defexception [:message]
end
