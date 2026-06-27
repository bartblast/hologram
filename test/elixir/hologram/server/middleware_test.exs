defmodule Hologram.Server.MiddlewareTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Server.Middleware

  alias Hologram.Server

  describe "run/2" do
    test "returns the server unchanged for an empty chain" do
      server = %Server{session: %{"locale" => "en"}}

      assert run(server, []) == server
    end

    test "folds the chain left to right, passing each middleware's opts" do
      append = fn server, value -> Server.append_response_header(server, "vary", value) end

      chain = [
        {append, "Accept"},
        {append, "Accept-Encoding"}
      ]

      assert run(%Server{}, chain).response_headers == %{"vary" => "Accept, Accept-Encoding"}
    end

    test "stops after a middleware sets a terminal status" do
      chain = [
        {fn server, _opts -> Server.put_status(server, 403) end, []},
        {fn server, _opts -> Server.put_response_header(server, "x-ran", "yes") end, []}
      ]

      result = run(%Server{}, chain)

      assert result.status == 403
      assert result.response_headers == %{}
    end

    test "skips the whole chain when the server is already terminal" do
      chain = [{fn server, _opts -> Server.put_response_header(server, "x-ran", "yes") end, []}]
      result = run(%Server{status: 302}, chain)

      assert result.status == 302
      assert result.response_headers == %{}
    end
  end
end
