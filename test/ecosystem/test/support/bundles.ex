defmodule HologramEcosystemTests.Bundles do
  # Reads the JavaScript bundles the compiler wrote for the app, for the tests of what each holds.

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers

  # The content of the chunk bundle with the given digest.
  def chunk(digest) do
    static_dir()
    |> Path.join(RouterHelpers.chunk_bundle_path(digest))
    |> File.read!()
  end

  # Whether the chunk bundle with the given digest defines the given function (see defines?/2).
  def chunk_defines?(digest, mfa) do
    digest
    |> chunk()
    |> defines?(mfa)
  end

  # The digests of every chunk bundle the compiler wrote.
  def chunk_digests do
    static_dir()
    |> Path.join("hologram/chunk-????????.js")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".js"))
    |> Enum.map(&String.replace_prefix(&1, "chunk-", ""))
    |> Enum.sort()
  end

  # Whether the bundle defines the given function. A bundle can name a module without holding its
  # code (a protocol's dispatcher names every implementation), so the name alone says nothing.
  def defines?(bundle, {module, function, arity}) do
    String.contains?(
      bundle,
      ~s/defineElixirFunction("#{inspect(module)}","#{function}",#{arity},/
    )
  end

  # The content of the given page's bundle.
  def page(page_module) do
    digest = PageDigestRegistry.lookup(page_module)

    static_dir()
    |> Path.join(RouterHelpers.page_bundle_path(page_module, digest))
    |> File.read!()
  end

  # The content of the runtime bundle.
  def runtime do
    [runtime_bundle_path] =
      static_dir()
      |> Path.join("hologram/runtime-????????.js")
      |> Path.wildcard()

    File.read!(runtime_bundle_path)
  end

  defp static_dir do
    Application.app_dir(:hologram_ecosystem_tests, "priv/static")
  end
end
