defmodule Hologram.RouterTest do
  use Hologram.TestCase, async: true
  require Hologram.Router

  test "hologram/2" do
    ast =
      Macro.expand_once(
        quote do
          Hologram.Router.hologram("/test-path", TestPage)
        end,
        __ENV__
      )

    assert {:get, [],
            [
              "/test-path",
              {:__aliases__, [counter: _, alias: false], [:HologramController]},
              :index,
              [
                private:
                  {:%{}, [],
                   [
                     hologram_page: {:__aliases__, [counter: _, alias: false], [:TestPage]}
                   ]}
              ]
            ]} = ast
  end
end
