defmodule Hologram.Assets.Pipeline do
  @moduledoc false

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils

  def run(opts) do
    _assets_dir = opts[:assets_dir]
    dist_dir = opts[:dist_dir]
    tmp_dist_dir = Path.join(opts[:tmp_dir], "dist")

    _old_dist_files = list_old_dist_files(dist_dir)

    FileUtils.recreate_dir(tmp_dist_dir)
  end

  defp list_old_dist_files(dist_dir) do
    hologram_dir_prefix = Path.join(dist_dir, "hologram") <> PathUtils.path_separator()

    dist_dir
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.starts_with?(&1, hologram_dir_prefix))
  end
end
