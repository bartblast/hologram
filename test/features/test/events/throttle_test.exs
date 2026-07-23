defmodule HologramFeatureTests.Events.ThrottleTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.Throttle.Page1

  feature "throttle caps a burst to a leading and trailing dispatch while a plain binding fires on every event",
          %{session: session} do
    session
    |> visit(Page1)
    |> fill_in(css("#my_input"), with: "abcde")
    |> assert_text(css("#plain_result"), ~s/{5, "e"}/)
    |> assert_text(css("#throttled_result"), ~s/{2, "e"}/)
  end
end
