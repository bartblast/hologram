defmodule Hologram.Runtime.ControllerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Controller
  alias Hologram.Test.Fixtures.Runtime.Controller.Module1

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{aaa: "111", bbb: "222"}
  end
end
