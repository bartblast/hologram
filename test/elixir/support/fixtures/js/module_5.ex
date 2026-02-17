defmodule Hologram.Test.Fixtures.JS.Module5 do
  use Hologram.JS

  js_import("Chart", from: "chart.js", as: "MyChart")
  js_import("Chart", from: "chart.js", as: "MyChart")
end
