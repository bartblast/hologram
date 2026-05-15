defmodule Hologram.Realtime.SSETest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Realtime.SSE

  describe "prepare/1" do
    test "sets SSE response headers" do
      conn = Plug.Test.conn(:get, "/")
      result = SSE.prepare(conn)

      assert result.resp_headers == [
               {"cache-control", "no-cache"},
               {"connection", "keep-alive"},
               {"content-type", "text/event-stream"}
             ]
    end

    test "opens a chunked response with status 200" do
      conn = Plug.Test.conn(:get, "/")
      result = SSE.prepare(conn)

      assert result.state == :chunked
      assert result.status == 200
    end
  end
end
