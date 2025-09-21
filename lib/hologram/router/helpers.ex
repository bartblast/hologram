defmodule Hologram.Router.Helpers do
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Reflection

  @doc """
  Returns the relative path to the asset file in the dist directory (including digest) for the given source asset path.
  Raises Hologram.AssetNotFoundError if the asset is not found.
  """
  @spec asset_path(String.t()) :: String.t()
  def asset_path(source_asset_path) do
    case AssetPathRegistry.lookup(source_asset_path) do
      {:ok, dist_asset_path} ->
        dist_asset_path

      :error ->
        raise Hologram.AssetNotFoundError, "there is no such asset: \"#{source_asset_path}\""
    end
  end

  @doc """
  Returns the relative URL of a page's JavaScript bundle using the page's digest.
  """
  @spec page_bundle_path(String.t()) :: String.t()
  def page_bundle_path(page_digest) do
    "/hologram/page-#{page_digest}.js"
  end

  @doc """
  Builds relative URL for the given page module or a tuple of a page module and params.
  """
  @spec page_path(module | tuple) :: String.t()

  def page_path({module, params}) do
    page_path(module, params)
  end

  def page_path(module) do
    page_path(module, [])
  end

  @doc """
  Builds relative URL for the given page module and params.
  """
  @spec page_path(module, keyword | map) :: String.t()

  def page_path(page_module, params) when is_map(params) do
    page_path(page_module, Map.to_list(params))
  end

  def page_path(page_module, params) do
    required_params = page_module.__params__()
    initial_acc = {params, page_module.__route__()}

    {remaining_params, path} =
      Enum.reduce(required_params, initial_acc, fn {key, _type, _opts}, {params_acc, path_acc} ->
        if !Keyword.has_key?(params_acc, key) do
          raise ArgumentError,
                ~s'page "#{Reflection.module_name(page_module)}" expects "#{key}" param'
        end

        new_params_acc = Keyword.drop(params_acc, [key])
        new_path_acc = String.replace(path_acc, ":#{key}", to_string(params[key]))

        {new_params_acc, new_path_acc}
      end)

    if remaining_params != [] do
      {key, _value} = hd(remaining_params)

      raise ArgumentError,
            ~s/page "#{Reflection.module_name(page_module)}" doesn't expect "#{key}" param/
    end

    path
  end
end
