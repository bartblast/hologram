defmodule Hologram.Runtime.ControllerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Controller
  alias Hologram.Test.Fixtures.Runtime.Controller.Module1

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{aaa: "111", bbb: "222"}
  end

  test "handle_request/2" do
    conn = Plug.Test.conn(:get, "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")

    expected = %{
      conn
      | halted: true,
        resp_body: "param_aaa = 111, param_bbb = 222",
        resp_headers: [
          {"content-type", "text/html; charset=utf-8"},
          {"cache-control", "max-age=0, private, must-revalidate"}
        ],
        state: :sent,
        status: 200
    }

    assert handle_request(conn, Module1) == expected
  end
end
