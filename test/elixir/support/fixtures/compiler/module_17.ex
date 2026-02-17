defmodule Hologram.Test.Fixtures.Compiler.Module17 do
  use Hologram.JS

  js_import "formatDate", from: "./utils.js", as: "myFormatDate"
end
