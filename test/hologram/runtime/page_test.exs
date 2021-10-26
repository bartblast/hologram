defmodule Hologram.PageTest do
  use Hologram.Test.UnitCase, async: true
  require Hologram.Page
  alias Hologram.Page

  @default_layout Application.get_env(:hologram, :default_layout)

  describe "layout/0" do
    test "default layout" do
      page_module = Hologram.Test.Fixtures.Runtime.Page.Module1
      result = page_module.layout()

      assert result == @default_layout
    end

    test "non-default layout" do
      page_module = Hologram.Test.Fixtures.Runtime.Page.Module2
      result = page_module.layout()

      assert result == :test_layout
    end
  end

  test "layout/1" do
    ast =
      Macro.expand_once(
        quote do
          Hologram.Page.layout(Hologram.PageTest)
        end,
        __ENV__
      )

    assert {
             :def,
             [context: Hologram.Page, import: Kernel],
             [
               {:custom_layout, [counter: _, context: Hologram.Page], Hologram.Page},
               [do: {:__aliases__, [counter: _, alias: false], [:Hologram, :PageTest]}]
             ]
           } = ast
  end

  test "route/1" do
    ast =
      Macro.expand_once(
        quote do
          Hologram.Page.route("/test-path")
        end,
        __ENV__
      )

    assert {:def, [context: Hologram.Page, import: Kernel],
            [{:route, [counter: _, context: Hologram.Page], Hologram.Page}, [do: "/test-path"]]} =
             ast
  end
end
