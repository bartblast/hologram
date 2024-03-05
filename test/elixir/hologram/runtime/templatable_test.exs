defmodule Hologram.Runtime.TemplatableTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Templatable
  alias Hologram.Component

  test "put_context/3" do
    component = %Component{context: %{a: 1}}

    assert put_context(component, :b, 2) == %Component{
             context: %{a: 1, b: 2}
           }
  end

  describe "put_state/3" do
    test "keyword" do
      component = %Component{state: %{a: 1}}

      assert put_state(component, b: 2, c: 3) == %Component{
               state: %{a: 1, b: 2, c: 3}
             }
    end

    test "map" do
      component = %Component{state: %{a: 1}}

      assert put_state(component, %{b: 2, c: 3}) == %Component{
               state: %{a: 1, b: 2, c: 3}
             }
    end
  end

  test "put_state/3" do
    component = %Component{state: %{a: 1}}

    assert put_state(component, :b, 2) == %Component{
             state: %{a: 1, b: 2}
           }
  end
end
