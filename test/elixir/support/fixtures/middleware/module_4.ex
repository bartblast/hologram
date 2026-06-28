defmodule Hologram.Test.Fixtures.Middleware.Module4 do
  use Hologram.Middleware

  alias Hologram.Test.Fixtures.Middleware.Module1
  alias Hologram.Test.Fixtures.Middleware.Module2

  middleware Module2
  middleware Module1, value: "b"
end
