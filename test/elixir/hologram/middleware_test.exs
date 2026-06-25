defmodule Hologram.MiddlewareTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Server
  alias Hologram.Test.Fixtures.Middleware.Module3
  alias Hologram.Test.Fixtures.Middleware.Module4

  describe "call/2" do
    test "a group folds its declared sub-chain over the server" do
      assert Module3.call(%Server{}, []).response_headers == %{"vary" => "a, b"}
    end

    test "a group short-circuits its sub-chain on a terminal status" do
      result = Module4.call(%Server{}, [])

      assert result.status == 403
      assert result.response_headers == %{}
    end
  end
end
