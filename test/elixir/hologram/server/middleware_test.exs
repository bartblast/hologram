defmodule Hologram.Server.MiddlewareTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Server.Middleware

  alias Hologram.Server

  describe "run/2" do
    test "returns the given Server struct for an inline result" do
      result = %Server{response_body: "inline result"}

      assert run(%Server{}, result) == result
    end

    test "returns the server unchanged for an empty step list" do
      server = %Server{session: %{"locale" => "en"}}

      assert run(server, []) == server
    end

    test "folds steps left to right" do
      steps = [
        fn server -> Server.append_response_header(server, "vary", "Accept") end,
        fn server -> Server.append_response_header(server, "vary", "Accept-Encoding") end
      ]

      assert run(%Server{}, steps).response_headers == %{"vary" => "Accept, Accept-Encoding"}
    end

    test "expands a step that returns a list of steps" do
      bundle = fn _server ->
        [
          fn server -> Server.append_response_header(server, "vary", "Accept-Encoding") end,
          fn server -> Server.append_response_header(server, "vary", "Cookie") end
        ]
      end

      steps = [
        fn server -> Server.append_response_header(server, "vary", "Accept") end,
        bundle,
        fn server -> Server.append_response_header(server, "vary", "User-Agent") end
      ]

      assert run(%Server{}, steps).response_headers == %{
               "vary" => "Accept, Accept-Encoding, Cookie, User-Agent"
             }
    end

    test "stops after a step sets a terminal status" do
      steps = [
        fn server -> Server.put_status(server, 403) end,
        fn server -> Server.put_response_header(server, "x-ran", "yes") end
      ]

      result = run(%Server{}, steps)

      assert result.status == 403
      assert result.response_headers == %{}
    end

    test "skips all steps when the server is already terminal" do
      steps = [fn server -> Server.put_response_header(server, "x-ran", "yes") end]

      result = run(%Server{status: 302}, steps)

      assert result.status == 302
      assert result.response_headers == %{}
    end

    test "short-circuits within an expanded bundle" do
      bundle = fn _server ->
        [
          fn server -> Server.put_status(server, 401) end,
          fn server -> Server.put_response_header(server, "x-ran", "yes") end
        ]
      end

      steps = [bundle, fn server -> Server.put_response_header(server, "x-ran-too", "yes") end]

      result = run(%Server{}, steps)

      assert result.status == 401
      assert result.response_headers == %{}
    end
  end
end
