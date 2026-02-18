# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module18 do
  use Hologram.JS

  js_import "Chart", from: "chart.js", as: "MyChart"

  def my_fun, do: :ok
end
