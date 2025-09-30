defmodule Hologram.Assets.Pipeline do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils

  def run(opts) do
    assets_dir = opts[:assets_dir]
    dist_dir = opts[:dist_dir]

    _old_dist_files = list_old_dist_files(dist_dir)

    assets_dir
    |> list_assets()
    |> stream_extract_asset_infos(assets_dir)
    |> stream_read_assets()
    |> stream_digest_assets(dist_dir)
    |> stream_compress_assets()
    |> Stream.run()
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

  defp list_old_dist_files(dist_dir) do
    hologram_dir_prefix = Path.join(dist_dir, "hologram") <> PathUtils.path_separator()

    dist_dir
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.starts_with?(&1, hologram_dir_prefix))
  end

  defp stream_compress_assets(_todo), do: :todo

  defp stream_digest_assets(assets, dist_dir) do
    Stream.each(assets, fn asset ->
      digest = CryptographicUtils.digest(asset.content, :md5, :hex)

      digested_asset_name = "#{asset.name}-#{digest}#{asset.extension}"
      digested_asset_path = Path.join([dist_dir, asset.relative_dir, digested_asset_name])

      FileUtils.write_p!(digested_asset_path, asset.content)
    end)
  end

  defp stream_extract_asset_infos(asset_paths, assets_dir) do
    Stream.map(asset_paths, fn asset_path ->
      extension = Path.extname(asset_path)

      relative_dir =
        asset_path
        |> Path.dirname()
        |> Path.relative_to(assets_dir)

      %{
        extension: extension,
        name: Path.basename(asset_path, extension),
        path: asset_path,
        relative_dir: relative_dir
      }
    end)
  end

  defp stream_read_assets(assets) do
    Stream.map(assets, fn asset ->
      content = File.read!(asset.path)
      Map.put(asset, :content, content)
    end)
  end
end
