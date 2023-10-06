defmodule Hologram.Runtime.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.Controller
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.PageDigestRegistry
  alias Hologram.Test.Fixtures.Runtime.Controller.Module1

  defmodule Stub do
    @behaviour PageDigestRegistry

    def dump_path, do: "#{Reflection.tmp_path()}/#{__MODULE__}.plt"

    def ets_table_name, do: __MODULE__
  end

  setup :set_mox_global

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{aaa: "111", bbb: "222"}
  end

  describe "handle_request/2" do
    setup do
      stub_with(PageDigestRegistry.Mock, Stub)
      setup_page_digest_registry(Stub)

      :ok
    end

    test "conn updates" do
      ETS.put(Stub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        Plug.Test.conn(:get, "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")

      assert handle_request(conn, Module1) == %{
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
    end
  end
end
