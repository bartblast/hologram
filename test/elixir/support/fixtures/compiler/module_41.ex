defmodule Hologram.Test.Fixtures.Compiler.Module41 do
  use Hologram.JS

  @missing_js_fixture_path Path.join(__DIR__, "missing_js_fixture.mjs")

  js_import :get, from: "lodash/get.js"
  js_import :withGlobal, from: "@sinonjs/fake-timers"
  js_import :missing, from: @missing_js_fixture_path
end
