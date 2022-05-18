# DEFER: refactor & test

defmodule Mix.Tasks.Compile.Hologram do
  use Mix.Task.Compiler
  require Logger

  alias Hologram.Compiler
  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  def run(opts \\ []) do
    Logger.debug("Hologram: compiler started")

    if has_source?() do
      source_digest =
        list_source_files(opts)
        |> digest_files()

      if !has_source_digest?() || has_source_changes?(source_digest) || opts[:force] do
        Compiler.compile(opts)
        save_source_digest(source_digest)
      end
    end

    Logger.debug("Hologram: compiler finished")

    :ok
  end

  defp digest_files(paths) do
    data =
      Enum.reduce(paths, [], &(&2 ++ Utils.list_files_recursively(&1)))
      |> Enum.reduce(%{}, &Map.put(&2, &1, File.read!(&1)))
      |> :erlang.term_to_binary()

    :crypto.hash(:md5, data)
  end

  defp has_source? do
    Reflection.mix_path()
    |> File.exists?()
  end

  defp has_source_changes?(new_source_digest) do
    old_source_digest =
      Reflection.root_source_digest_path()
      |> File.read!()

    new_source_digest != old_source_digest
  end

  defp has_source_digest? do
    Reflection.root_source_digest_path()
    |> File.exists?()
  end

  defp list_source_files(opts) do
    [
      Reflection.app_path(opts),
      Reflection.lib_path(opts),
      Reflection.mix_path(opts),
      Reflection.mix_lock_path(opts)
    ]
  end

  defp save_source_digest(source_digest) do
    Reflection.root_source_digest_path()
    |> File.write!(source_digest)
  end
end
