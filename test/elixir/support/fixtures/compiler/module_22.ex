# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module22 do
  use Hologram.JS

  js_import "formatDate", from: "./utils.js", as: "myFormatDate"

  def my_fun, do: :ok
end
