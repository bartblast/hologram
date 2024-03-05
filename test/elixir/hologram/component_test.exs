defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Commons.Reflection
  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Component.Module1
  alias Hologram.Test.Fixtures.Component.Module2
  alias Hologram.Test.Fixtures.Component.Module3
  alias Hologram.Test.Fixtures.Component.Module4

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  test "__props__/0" do
    assert Module4.__props__() == [{:b, :integer, [opt_1: 111, opt_2: 222]}, {:a, :string, []}]
  end

  test "colocated_template_path/1" do
    assert colocated_template_path("/my_dir_1/my_dir_2/my_dir_3/my_file.ex") ==
             "/my_dir_1/my_dir_2/my_dir_3/my_file.holo"
  end

  describe "init/2" do
    test "no default implementation" do
      refute Reflection.has_function?(Module1, :init, 2)
    end

    test "overridden implementation" do
      assert Module2.init(:props_dummy, build_component_struct()) == %Component{
               state: %{overriden: true}
             }
    end
  end

  describe "init/3" do
    test "default implementation" do
      assert Reflection.has_function?(Module1, :init, 3)
    end

    test "overridden implementation" do
      assert Module2.init(:props_dummy, build_component_struct(), build_server_struct()) ==
               {%Component{state: %{overriden: true}}, %Server{}}
    end
  end

  describe "maybe_define_template_fun/1" do
    test "valid template path" do
      template_path = "#{@fixtures_path}/template/template_1.holo"

      assert maybe_define_template_fun(template_path, Component) ==
               {:__block__, [],
                [
                  {:@, [context: Component, imports: [{1, Kernel}]],
                   [{:impl, [context: Component], [Component]}]},
                  {:def, [context: Component, imports: [{1, Kernel}, {2, Kernel}]],
                   [
                     {:template, [context: Component], Component},
                     [do: {:sigil_H, [], ["My template 1", []]}]
                   ]}
                ]}
    end

    test "invalid template path" do
      refute maybe_define_template_fun("/my_invalid_template_path.holo", Component)
    end
  end

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      assert Module3.template().(%{}) == [text: "Module3 template"]
    end
  end
end
