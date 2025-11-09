defmodule Hologram.Router.Helpers do
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Reflection

  @doc """
  Retrieves the asset path, including the digest, for the specified static file within the static directory.
  If there's no corresponding entry for the provided static file, the static file path itself will be returned.
  """
  @spec asset_path(String.t()) :: String.t()
  def asset_path(static_path) do
    case AssetPathRegistry.lookup(static_path) do
      {:ok, asset_path} ->
        asset_path

      :error ->
        raise Hologram.AssetNotFoundError, "there is no such asset: \"#{static_path}\""
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
      Enum.reduce(required_params, initial_acc, &process_param(&1, &2, page_module, params))

    ensure_no_extra_params!(remaining_params, page_module)

    path
  end

  defp encode_param_value(value) do
    value
    |> to_string()
    |> uri_encode()
  end

  defp ensure_no_extra_params!([], _page_module), do: :ok

  defp ensure_no_extra_params!(remaining_params, page_module) do
    {key, _value} = hd(remaining_params)

    raise ArgumentError,
          ~s/page "#{Reflection.module_name(page_module)}" doesn't expect "#{key}" param/
  end

  defp ensure_param_exists!(params, key, page_module) do
    if not Keyword.has_key?(params, key) do
      raise ArgumentError,
            ~s'page "#{Reflection.module_name(page_module)}" expects "#{key}" param'
    end
  end

  defp process_param({key, _type, _opts}, {params_acc, path_acc}, page_module, original_params) do
    ensure_param_exists!(params_acc, key, page_module)

    encoded_value = encode_param_value(original_params[key])
    new_path = String.replace(path_acc, ":#{key}", encoded_value)
    new_params = Keyword.drop(params_acc, [key])

    {new_params, new_path}
  end

  defp uri_encode(".."), do: "%2E%2E"

  defp uri_encode("."), do: "%2E"

  defp uri_encode(str_value) do
    URI.encode(str_value, &URI.char_unreserved?/1)
  end
end
