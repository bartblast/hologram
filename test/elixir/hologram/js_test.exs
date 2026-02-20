defmodule Hologram.JSTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.JS.Module1
  alias Hologram.Test.Fixtures.JS.Module2
  alias Hologram.Test.Fixtures.JS.Module3
  alias Hologram.Test.Fixtures.JS.Module4
  alias Hologram.Test.Fixtures.JS.Module6

  describe "js_import/2" do
    test "no imports" do
      assert Module2.__js_imports__() == []
    end

    test "single import without alias" do
      assert Module3.__js_imports__() == [
               %{export: "Chart", from: "chart.js", as: "Chart"}
             ]
    end

    test "single import with alias" do
      assert Module4.__js_imports__() == [
               %{export: "Chart", from: "chart.js", as: "MyChart"}
             ]
    end

    test "multiple imports from same source" do
      assert Module1.__js_imports__() == [
               %{export: "Chart", from: "chart.js", as: "MyChart"},
               %{export: "helpers", from: "chart.js", as: "helpers"}
             ]
    end

    test "multiple imports from different sources" do
      assert Module6.__js_imports__() == [
               %{export: "Chart", from: "chart.js", as: "Chart"},
               %{export: "helpers", from: "chart.js", as: "helpers"},
               %{export: "formatDate", from: "utils.js", as: "myFormatDate"}
             ]
    end

    test "resolves ./ relative path to assets/js/" do
      resolved_path =
        Path.join([Reflection.root_dir(), "assets", "js", "utils.js"])

      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.JS.RelativeDotSlash do
          use Hologram.JS

          js_import :foo, from: "./utils.js", as: :foo
        end
        """)

      assert module.__js_imports__() == [
               %{export: "foo", from: resolved_path, as: "foo"}
             ]
    end

    test "resolves ../ relative path to assets/js/" do
      resolved_path =
        Path.join([Reflection.root_dir(), "assets", "vendor", "utils.js"])

      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.JS.RelativeDotDotSlash do
          use Hologram.JS

          js_import :foo, from: "../vendor/utils.js", as: :foo
        end
        """)

      assert module.__js_imports__() == [
               %{export: "foo", from: resolved_path, as: "foo"}
             ]
    end

    test "keeps absolute path as-is" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.JS.AbsolutePath do
          use Hologram.JS

          js_import :foo, from: "/absolute/path/utils.js", as: :foo
        end
        """)

      assert module.__js_imports__() == [
               %{export: "foo", from: "/absolute/path/utils.js", as: "foo"}
             ]
    end

    test "keeps npm package specifier as-is" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.JS.NpmPackage do
          use Hologram.JS

          js_import :Chart, from: "chart.js", as: :Chart
        end
        """)

      assert module.__js_imports__() == [
               %{export: "Chart", from: "chart.js", as: "Chart"}
             ]
    end

    test "raises on duplicate binding name" do
      expected_error_msg =
        ~s'duplicate JS binding name "MyChart" in Hologram.Test.Fixtures.JS.DuplicateBindingName'

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.JS.DuplicateBindingName do
          use Hologram.JS

          js_import :Chart, from: "chart.js", as: :MyChart
          js_import :Other, from: "other.js", as: :MyChart
        end
        """)
      end
    end
  end
end
