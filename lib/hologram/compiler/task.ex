# DEFER: test

defmodule Mix.Tasks.Compile.Hologram do
  use Mix.Task.Compiler

  alias Hologram.Compiler.{Builder, Helpers}
  alias Hologram.Runtime.Reflection

  @cwd File.cwd!()

  def run(_) do
    "#{@cwd}/priv/static/hologram"
    |> File.mkdir_p!()

    remove_old_files()

    # DEFER: parallelize
    Reflection.list_pages()
    |> Enum.map(&build_page/1)
    |> build_manifest()

    :ok
  end

  defp build_manifest(digests) do
    json =
      Enum.into(digests, %{})
      |> Jason.encode!()

    "#{@cwd}/priv/static/hologram/manifest.json"
    |> File.write!(json)
  end

  defp build_page(page) do
    js =
      Helpers.module_segments(page)
      |> Builder.build()

    digest =
      :crypto.hash(:md5, js)
      |> Base.encode16()
      |> String.downcase()

    "#{@cwd}/priv/static/hologram/page-#{digest}.js"
    |> File.write!(js)

    {page, digest}
  end

  defp remove_old_files do
    "#{@cwd}/priv/static/hologram/*"
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)
  end
end
