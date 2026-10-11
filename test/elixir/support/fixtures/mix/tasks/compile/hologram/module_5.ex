defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module5 do
  use Hologram.Component
  use Hologram.JS

  @js_fixture_path Path.join(__DIR__, "runtime_js_fixture.mjs")

  js_import :export_1, from: @js_fixture_path, as: :alias_1

  @impl Component
  def template do
    ~HOLO""
  end
end
