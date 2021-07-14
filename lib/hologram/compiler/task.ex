# DEFER: test

defmodule Mix.Tasks.Compile.Hologram do
  use Mix.Task.Compiler

  alias Hologram.Compiler.{Builder, Helpers}
  alias Hologram.Runtime.Reflection

  def run(_) do
    File.cwd!() <> "/priv/static/hologram"
    |> File.mkdir_p!()

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

    File.cwd!() <> "/priv/static/hologram/manifest.json"
    |> File.write!(json)
  end

  defp build_page(page) do
    js =
      Helpers.module_name_segments(page)
      |> Builder.build()

    digest =
      :crypto.hash(:md5, js)
      |> Base.encode16()
      |> String.downcase()

    File.cwd!() <> "/priv/static/hologram/page-#{digest}.js"
    |> File.write!(js)

    {page, digest}
  end
end
