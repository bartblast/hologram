defmodule Hologram.Test.Fixtures.JS.Module4 do
  use Hologram.JS

  js_import :Chart, from: "chart.js", as: :MyChart
end
