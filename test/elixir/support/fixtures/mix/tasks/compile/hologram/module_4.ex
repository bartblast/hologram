# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module4 do
  use Hologram.JS

  @js_fixture_path Path.join(__DIR__, "js_fixture.mjs")

  js_import :export_1, from: @js_fixture_path, as: :alias_1

  def my_fun, do: ""
end
