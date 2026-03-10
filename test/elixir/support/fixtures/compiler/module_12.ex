defmodule Hologram.Test.Fixtures.Compiler.Module12 do
  use Hologram.JS

  js_import :Chart, from: "chart.js", as: :MyChart
  js_import :helpers, from: "chart.js"
end
