defmodule Hologram.Test.Fixtures.Middleware.Module3 do
  use Hologram.Middleware

  alias Hologram.Test.Fixtures.Middleware.Module1

  middleware Module1, value: "a"
  middleware Module1, value: "b"
end
