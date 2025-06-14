defmodule Hologram.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Controller
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Controller.Module1

  use_module_stub :page_digest_registry

  setup :set_mox_global

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{aaa: "111", bbb: "222"}
  end

  describe "handle_request/2" do
    setup do
      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "conn updates" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")
        |> Plug.Conn.fetch_cookies()
        |> handle_request(Module1)

      assert conn.halted == true
      assert conn.resp_body == "param_aaa = 111, param_bbb = 222"
      assert conn.state == :sent
      assert conn.status == 200

      assert Map.has_key?(conn.resp_cookies, "hologram_session")
    end
  end
end
