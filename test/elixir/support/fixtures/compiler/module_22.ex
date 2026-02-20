# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module22 do
  use Hologram.JS

  @js_fixture_path Path.join(__DIR__, "js_fixture_2.mjs")

  js_import :export_2, from: @js_fixture_path, as: :alias_2

  def my_fun, do: :ok
end
