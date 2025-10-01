defmodule Hologram.Assets.Pipeline do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils

  @doc """
  Bundles and processes assets (CSS, JS, images, fonts, etc.) for distribution.
  """
  @spec run(keyword()) :: :ok
  def run(opts) do
    assets_dir = opts[:assets_dir]
    dist_dir = opts[:dist_dir]

    old_dist_paths = list_old_dist_paths(dist_dir)

    new_dist_paths =
      assets_dir
      |> list_assets()
      |> process_assets_async(assets_dir, dist_dir)
      |> collect_new_dist_paths()

    remove_old_dist_files(old_dist_paths, new_dist_paths)

    :ok
  end

  defp collect_new_dist_paths(assets) do
    Enum.flat_map(assets, fn asset ->
      [asset.digested_asset_path, asset.compressed_asset_path]
    end)
  end

  defp compress_and_write_asset(asset) do
    compressed_content = :zlib.gzip(asset.content)
    compressed_asset_path = asset.digested_asset_path <> ".gz"

    File.write!(compressed_asset_path, compressed_content)

    Map.put(asset, :compressed_asset_path, compressed_asset_path)
  end

  defp digest_and_write_asset(asset, dist_dir) do
    digest = CryptographicUtils.digest(asset.content, :md5, :hex)
    digested_asset_name = "#{asset.basename}-#{digest}#{asset.extension}"
    digested_asset_path = Path.join([dist_dir, asset.relative_dir, digested_asset_name])

    FileUtils.write_p!(digested_asset_path, asset.content)

    Map.put(asset, :digested_asset_path, digested_asset_path)
  end

  defp extract_asset_info(asset_path, assets_dir) do
    extension = Path.extname(asset_path)

    relative_dir =
      asset_path
      |> Path.dirname()
      |> Path.relative_to(assets_dir)

    %{
      basename: Path.basename(asset_path, extension),
      extension: extension,
      path: asset_path,
      relative_dir: relative_dir
    }
  end

  defp list_assets(assets_dir) do
    list_fonts(assets_dir) ++ list_images(assets_dir)
  end

  defp list_fonts(assets_dir) do
    fonts_dir = Path.join(assets_dir, "fonts")
    FileUtils.list_files_recursively(fonts_dir)
  end

  defp list_images(assets_dir) do
    images_dir = Path.join(assets_dir, "images")
    FileUtils.list_files_recursively(images_dir)
  end

  defp list_old_dist_paths(dist_dir) do
    hologram_dir_prefix = Path.join(dist_dir, "hologram") <> PathUtils.path_separator()

    dist_dir
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.starts_with?(&1, hologram_dir_prefix))
  end

  # Process all assets concurrently for better I/O and CPU utilization
  defp process_assets_async(asset_paths, assets_dir, dist_dir) do
    asset_paths
    |> Task.async_stream(
      fn asset_path ->
        asset_path
        |> extract_asset_info(assets_dir)
        |> read_asset_content()
        |> digest_and_write_asset(dist_dir)
        |> compress_and_write_asset()
      end,
      # Good concurrency for I/O
      max_concurrency: System.schedulers_online() * 2,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp read_asset_content(asset) do
    content = File.read!(asset.path)
    Map.put(asset, :content, content)
  end

  defp remove_old_dist_files(old_dist_paths, new_dist_paths) do
    # Kernel.--/2 can be more performant for small lists due to lower overhead,
    # but MapSet.difference/2 becomes faster as size grows.
    files_to_remove = old_dist_paths -- new_dist_paths

    Enum.each(files_to_remove, fn file_path ->
      File.rm!(file_path)
    end)
  end
end
