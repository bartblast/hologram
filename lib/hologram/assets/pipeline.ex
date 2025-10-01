defmodule Hologram.Assets.Pipeline do
  @moduledoc false

  alias Hologram.Assets.Pipeline.Tailwind
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils

  # Supported asset types for processing (used for validation)
  @asset_types [:css, :font, :image]

  # Processing pipeline steps for each asset type
  @pipeline_steps %{
    css: :TODO,
    font: [
      :info,
      :read,
      :digest,
      :write,
      :compress
    ],
    image: [
      :info,
      :read,
      :digest,
      :write,
      :compress
    ]
  }

  @doc """
  Bundles and processes assets (CSS, JS, images, fonts, etc.) for distribution.

  The processing pipeline is configurable per asset type through the @pipeline_steps
  module attribute. Each asset type can have a different sequence of processing steps.

  Available pipeline steps:
  - :compress - Create gzipped version of the asset  
  - :digest - Generate content hash and digested filename
  - :info - Extract file metadata and type information
  - :read - Read file content into memory
  - :write - Write asset content to digested file path

  To add a new asset type or modify processing steps, update the @pipeline_steps
  module attribute with the desired configuration.
  """
  @spec run(keyword()) :: :ok
  def run(opts) do
    assets_dir = opts[:assets_dir]
    dist_dir = opts[:dist_dir]

    old_dist_paths = list_old_dist_paths(dist_dir)

    new_dist_paths =
      assets_dir
      |> list_assets()
      |> process_static_assets(assets_dir, dist_dir)
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

  defp determine_css_bundler do
    if Tailwind.installed?() do
      :tailwind
    else
      :esbuild
    end
  end

  defp digest_asset(asset) do
    digest = CryptographicUtils.digest(asset.content, :md5, :hex)
    digested_asset_name = "#{asset.basename}-#{digest}#{asset.extension}"

    Map.put(asset, :digested_asset_name, digested_asset_name)
  end

  defp execute_pipeline({asset_path, asset_type}, assets_dir, dist_dir) do
    if asset_type not in @asset_types do
      raise ArgumentError,
            "Unsupported asset type: #{asset_type}. Supported types: #{inspect(@asset_types)}"
    end

    pipeline_steps = Map.get(@pipeline_steps, asset_type, @pipeline_steps.font)

    Enum.reduce(pipeline_steps, {asset_path, assets_dir, dist_dir}, fn step, acc ->
      case step do
        :compress ->
          compress_and_write_asset(acc)

        :digest ->
          {asset, _dist_dir} = acc
          digest_asset(asset)

        :write ->
          {asset, _dist_dir} = acc
          write_asset(asset, dist_dir)

        :info ->
          {path, assets_dir, _dist_dir} = acc
          extract_asset_info(path, assets_dir, asset_type)

        :read ->
          read_asset_content(acc)
      end
    end)
  end

  defp extract_asset_info(asset_path, assets_dir, asset_type) do
    extension = Path.extname(asset_path)

    relative_dir =
      asset_path
      |> Path.dirname()
      |> Path.relative_to(assets_dir)

    %{
      basename: Path.basename(asset_path, extension),
      extension: extension,
      path: asset_path,
      relative_dir: relative_dir,
      type: asset_type
    }
  end

  defp list_assets(assets_dir) do
    list_css(assets_dir) ++ list_fonts(assets_dir) ++ list_images(assets_dir)
  end

  defp list_css(assets_dir) do
    css_dir = Path.join(assets_dir, "css")

    css_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".css"))
    |> Enum.map(&{Path.join(css_dir, &1), :css})
  end

  defp list_fonts(assets_dir) do
    fonts_dir = Path.join(assets_dir, "fonts")

    fonts_dir
    |> FileUtils.list_files_recursively()
    |> Enum.map(&{&1, :font})
  end

  defp list_images(assets_dir) do
    images_dir = Path.join(assets_dir, "images")

    images_dir
    |> FileUtils.list_files_recursively()
    |> Enum.map(&{&1, :image})
  end

  defp list_old_dist_paths(dist_dir) do
    hologram_dir_prefix = Path.join(dist_dir, "hologram") <> PathUtils.path_separator()

    dist_dir
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.starts_with?(&1, hologram_dir_prefix))
  end

  # Process all static assets concurrently for better I/O and CPU utilization
  defp process_static_assets(assets, assets_dir, dist_dir) do
    assets
    |> Task.async_stream(
      &execute_pipeline(&1, assets_dir, dist_dir),
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

  defp write_asset(asset, dist_dir) do
    digested_asset_path = Path.join([dist_dir, asset.relative_dir, asset.digested_asset_name])

    FileUtils.write_p!(digested_asset_path, asset.content)

    Map.put(asset, :digested_asset_path, digested_asset_path)
  end
end
