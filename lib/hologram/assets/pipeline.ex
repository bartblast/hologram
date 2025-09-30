defmodule Hologram.Assets.Pipeline do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils

  def run(opts) do
    assets_dir = opts[:assets_dir]
    dist_dir = opts[:dist_dir]
    tmp_dist_dir = Path.join(opts[:tmp_dir], "dist")

    _old_dist_files = list_old_dist_files(dist_dir)

    FileUtils.recreate_dir(tmp_dist_dir)

    copy_assets(assets_dir, tmp_dist_dir)

    tmp_dist_dir
    |> FileUtils.list_files_recursively()
    |> Stream.map(&{&1, File.read!(&1)})
    |> stream_digest()
  end

  defp copy_assets(assets_dir, tmp_dist_dir) do
    maybe_copy_images(assets_dir, tmp_dist_dir)
  end

  defp list_old_dist_files(dist_dir) do
    hologram_dir_prefix = Path.join(dist_dir, "hologram") <> PathUtils.path_separator()

    dist_dir
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.starts_with?(&1, hologram_dir_prefix))
  end

  defp maybe_copy_images(assets_dir, tmp_dist_dir) do
    images_source_path = Path.join(assets_dir, "images")

    if File.exists?(images_source_path) do
      images_target_path = Path.join(tmp_dist_dir, "images")
      File.cp_r!(images_source_path, images_target_path)
    end
  end

  defp stream_digest(file_infos) do
    Stream.each(file_infos, fn {file_path, file_content} ->
      file_extension = Path.extname(file_path)
      file_name = Path.basename(file_path, file_extension)
      file_dir = Path.dirname(file_path)

      digest = CryptographicUtils.digest(file_content, :md5, :hex)
      digested_file_name = "#{file_name}-#{digest}#{file_extension}"
      digested_file_path = Path.join(file_dir, digested_file_name)
      File.write!(digested_file_path, file_content)
    end)
  end
end
