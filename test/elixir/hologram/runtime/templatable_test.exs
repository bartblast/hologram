defmodule Hologram.Runtime.TemplatableTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Templatable

  alias Hologram.Component
  alias Hologram.Runtime.Templatable

  describe "maybe_define_template_fun/1" do
    test "valid template path" do
      template_path = "#{@fixtures_path}/template/template_1.holo"

      assert maybe_define_template_fun(template_path, Component) ==
               {:__block__, [],
                [
                  {:@, [context: Templatable, imports: [{1, Kernel}]],
                   [{:impl, [context: Templatable], [Hologram.Component]}]},
                  {:def, [context: Templatable, imports: [{1, Kernel}, {2, Kernel}]],
                   [
                     {:template, [context: Templatable], Templatable},
                     [do: {:sigil_H, [], ["My template 1", []]}]
                   ]}
                ]}
    end

    test "invalid template path" do
      refute maybe_define_template_fun("/my_invalid_template_path.holo", Component)
    end
  end

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
