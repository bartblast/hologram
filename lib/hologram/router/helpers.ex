defmodule Hologram.Router.Helpers do
  alias Hologram.Runtime.AssetPathRegistry

  @doc """
  Retrieves the asset path, including the digest, for the specified static file within the static directory.
  If there's no corresponding entry for the provided static file, the static file path itself will be returned.
  """
  @spec asset_path(String.t()) :: String.t()
  def asset_path(static_path) do
    case AssetPathRegistry.lookup(static_path) do
      {:ok, asset_path} -> asset_path
      :error -> Path.join("/", static_path)
    end
  end
end
