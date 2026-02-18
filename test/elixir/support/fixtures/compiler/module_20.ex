# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module20 do
  use Hologram.JS

  js_import "Chart", from: "chart.js", as: "MyChart"
  js_import "helpers", from: "chart.js"

  def my_fun, do: :ok
end
