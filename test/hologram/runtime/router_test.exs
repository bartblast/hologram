defmodule Hologram.Runtime.RouterTest do
  use Hologram.Test.UnitCase, async: true
  require Hologram.Router

  test "hologram/2" do
    ast =
      Macro.expand_once(
        quote do
          Hologram.Router.hologram("/test-path", TestPage)
        end,
        __ENV__
      )

    assert {
             {:., [], [{:__aliases__, [alias: false], [:Hologram, :Router]}, :hologram]},
             [],
             ["/test-path", {:__aliases__, [alias: false], [:TestPage]}]
           } = ast
  end
end
