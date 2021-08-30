defmodule Hologram.PageTest do
  use Hologram.TestCase, async: true
  require Hologram.Page
  alias Hologram.Page

  test "route/1" do
    ast =
      Macro.expand_once(
        quote do
          Hologram.Page.route("/test-path")
        end,
        __ENV__
      )

    assert {:def, [context: Hologram.Page, import: Kernel], [{:route, [counter: _, context: Hologram.Page], Hologram.Page}, [do: "/test-path"]]} = ast
  end

  test "update/3" do
    assert Page.update(%{a: 1}, :b, 2) == %{a: 1, b: 2}
  end
end
