defmodule Hologram.AssetNotFoundError do
  @moduledoc """
  Raised when an asset can't be found.
  """

  defexception [:message]
end
