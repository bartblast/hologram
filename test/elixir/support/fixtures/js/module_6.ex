defmodule Hologram.Test.Fixtures.JS.Module6 do
  use Hologram.JS

  js_import "Chart", from: "chart.js"
  js_import "helpers", from: "chart.js"
  js_import "formatDate", from: "utils.js", as: "myFormatDate"
end
