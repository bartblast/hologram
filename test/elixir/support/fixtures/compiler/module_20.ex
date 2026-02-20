# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module20 do
  use Hologram.JS

  @js_fixture_path Path.join(__DIR__, "js_fixture_1.mjs")

  js_import :export_1a, from: @js_fixture_path, as: :alias_1a
  js_import :export_1b, from: @js_fixture_path, as: :alias_1b

  def my_fun, do: :ok
end
