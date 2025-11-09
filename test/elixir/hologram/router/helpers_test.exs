defmodule Hologram.Router.HelpersTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router.Helpers
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module3
  alias Hologram.Test.Fixtures.Router.Helpers.Module1
  alias Hologram.Test.Fixtures.Router.Helpers.Module2
  alias Hologram.Test.Fixtures.Router.Helpers.Module3
  alias Hologram.Test.Fixtures.Router.Helpers.Module4

  use_module_stub :asset_path_registry

  setup :set_mox_global

  describe "asset_path/1" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
    end

    test "asset exists" do
      assert asset_path("test_dir_1/test_dir_2/test_file_1.css") ==
               "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"
    end

    test "asset doesn't exist" do
      assert_raise Hologram.AssetNotFoundError,
                   "there is no such asset: \"invalid_file.css\"",
                   fn ->
                     asset_path("invalid_file.css")
                   end
    end
  end

  test "page_bundle_path/1" do
    assert page_bundle_path("abc") == "/hologram/page-abc.js"
  end

  describe "page_path/1" do
    test "module arg" do
      assert page_path(Module1) == "/hologram-test-fixtures-router-helpers-module1"
    end

    test "tuple arg" do
      assert page_path({Module2, param_1: :abc, param_2: 123}) ==
               "/hologram-test-fixtures-router-helpers-module2/abc/123"
    end
  end

  describe "page_path/2" do
    test "valid keyword params" do
      assert page_path(Module2, param_1: :abc, param_2: 123) ==
               "/hologram-test-fixtures-router-helpers-module2/abc/123"
    end

    test "valid map params" do
      assert page_path(Module2, %{param_1: :abc, param_2: 123}) ==
               "/hologram-test-fixtures-router-helpers-module2/abc/123"
    end

    test "URL encodes string params" do
      assert page_path(Module3, x: "hello world", y: "foo/bar") ==
               "/hologram-test-fixtures-router-helpers-module3/hello%20world/foo%2Fbar"
    end

    test "doesn't URL encode string dots in param values if the full value is not equal to '..' or '.'" do
      assert page_path(Module3, x: "..a..a..", y: ".b.b.") ==
               "/hologram-test-fixtures-router-helpers-module3/..a..a../.b.b."
    end

    test "URL encodes string '..' param value" do
      assert page_path(Module3, x: "..", y: "abc") ==
               "/hologram-test-fixtures-router-helpers-module3/%2F%2F/abc"
    end

    test "URL encodes string '.' param value" do
      assert page_path(Module3, x: ".", y: "abc") ==
               "/hologram-test-fixtures-router-helpers-module3/%2F/abc"
    end

    test "URL encodes atom params" do
      assert page_path(Module4, x: :"hello world", y: :"foo/bar") ==
               "/hologram-test-fixtures-router-helpers-module4/hello%20world/foo%2Fbar"
    end

    test "doesn't URL encode atom dots in param values if the full value is not equal to :.. or :." do
      assert page_path(Module4, x: :"..a..a..", y: :".b.b.") ==
               "/hologram-test-fixtures-router-helpers-module4/..a..a../.b.b."
    end

    test "URL encodes atom :.. param value" do
      assert page_path(Module4, x: :.., y: :abc) ==
               "/hologram-test-fixtures-router-helpers-module4/%2F%2F/abc"
    end

    test "URL encodes atom :. param value" do
      assert page_path(Module4, x: :., y: :abc) ==
               "/hologram-test-fixtures-router-helpers-module4/%2F/abc"
    end

    test "missing single param" do
      assert_raise ArgumentError,
                   ~s'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
                   fn ->
                     page_path(Module2, param_2: 123)
                   end
    end

    test "missing multiple params" do
      assert_raise ArgumentError,
                   ~s'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
                   fn ->
                     page_path(Module2, [])
                   end
    end

    test "extraneous single param" do
      assert_raise ArgumentError,
                   ~s/page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param/,
                   fn ->
                     page_path(Module2, param_1: :abc, param_2: 123, param_3: "xyz")
                   end
    end

    test "extraneous multiple params" do
      assert_raise ArgumentError,
                   ~s/page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param/,
                   fn ->
                     page_path(Module2, param_1: :abc, param_2: 123, param_3: "xyz", param_4: 987)
                   end
    end
  end
end
