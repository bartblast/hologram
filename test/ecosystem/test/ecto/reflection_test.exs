defmodule HologramEcosystemTests.Ecto.ReflectionTest do
  use HologramEcosystemTests.TestCase, async: false

  alias Hologram.Reflection
  alias HologramEcosystemTests.Bundles
  alias HologramEcosystemTests.Ecto.ClosedPage
  alias HologramEcosystemTests.Ecto.OpenPage
  alias HologramEcosystemTests.Ecto.Tag

  defp read_bundles(page) do
    Bundles.page(page) <> Bundles.runtime()
  end

  defp defines?(bundle, function, arity) do
    String.contains?(bundle, ~s/defineElixirFunction("#{inspect(Tag)}","#{function}",#{arity}/)
  end

  test "a real Ecto schema is known as one" do
    assert Reflection.ecto_schema?(Tag)
  end

  test "a page that calls no reflection function on its schema gets none" do
    bundle = read_bundles(ClosedPage)

    refute defines?(bundle, :__changeset__, 0)
    refute defines?(bundle, :__schema__, 1)
    refute defines?(bundle, :__schema__, 2)
  end

  test "a page whose client code calls a reflection function on its schema gets it" do
    bundle = read_bundles(OpenPage)

    assert defines?(bundle, :__changeset__, 0)
  end

  feature "the reflection function runs on the client", %{session: session} do
    session
    |> visit(OpenPage)
    |> click(button("Reflect"))
    |> assert_text(css("#fields"), "id,name")
  end
end
