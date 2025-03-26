defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Component
  alias Hologram.Component.Action
  alias Hologram.Component.Command
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Component.Module1
  alias Hologram.Test.Fixtures.Component.Module2
  alias Hologram.Test.Fixtures.Component.Module3
  alias Hologram.Test.Fixtures.Component.Module4

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  test "__props__/0" do
    assert Module4.__props__() == [{:a, :string, []}, {:b, :integer, [opt_1: 111, opt_2: 222]}]
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
      template_path = "#{@fixtures_dir}/template/template_1.holo"

      assert {:__block__, [],
              [
                {:@, [{:context, Component} | _imports_1],
                 [{:impl, [context: Component], [Component]}]},
                {:def, [{:context, Component} | _imports_2],
                 [
                   {:template, [context: Component], Component},
                   [do: {:sigil_HOLO, [], ["My template 1", []]}]
                 ]}
              ]} = maybe_define_template_fun(template_path, Component)
    end

    test "invalid template path" do
      refute maybe_define_template_fun("/my_invalid_template_path.holo", Component)
    end
  end

  describe "put_action/2, component struct" do
    test "name" do
      assert put_action(%Component{}, :my_action) == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      assert put_action(%Component{}, name: :my_action) == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      assert put_action(%Component{}, params: [a: 1, b: 2]) == %Component{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      assert put_action(%Component{}, target: "my_target") == %Component{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end
  end

  describe "put_action/2, server struct" do
    test "name" do
      assert put_action(%Server{}, :my_action) == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      assert put_action(%Server{}, name: :my_action) == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      assert put_action(%Server{}, params: [a: 1, b: 2]) == %Server{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      assert put_action(%Server{}, target: "my_target") == %Server{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end
  end

  test "put_action/3, component struct" do
    assert put_action(%Component{}, :my_action, a: 1, b: 2) == %Component{
             next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
           }
  end

  test "put_action/3, server struct" do
    assert put_action(%Server{}, :my_action, a: 1, b: 2) == %Server{
             next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
           }
  end

  describe "put_command/2" do
    test "name" do
      assert put_command(%Component{}, :my_command) == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      assert put_command(%Component{}, name: :my_command) == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      assert put_command(%Component{}, params: [a: 1, b: 2]) == %Component{
               next_command: %Command{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      assert put_command(%Component{}, target: "my_target") == %Component{
               next_command: %Command{name: nil, target: "my_target", params: %{}}
             }
    end
  end

  test "put_command/3" do
    assert put_command(%Component{}, :my_command, a: 1, b: 2) == %Component{
             next_command: %Command{name: :my_command, params: %{a: 1, b: 2}, target: nil}
           }
  end

  test "put_context/3" do
    component = %Component{emitted_context: %{a: 1}}

    assert put_context(component, :b, 2) == %Component{
             emitted_context: %{a: 1, b: 2}
           }
  end

  test "put_page/2" do
    assert put_page(%Component{}, MyPage) == %Component{next_page: MyPage}
  end

  test "put_page/3" do
    assert put_page(%Component{}, MyPage, a: 1, b: 2) == %Component{
             next_page: {MyPage, a: 1, b: 2}
           }
  end

  describe "put_state/2" do
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

  describe "put_state/3" do
    test "non-nested path" do
      component = %Component{state: %{a: 1}}

      assert put_state(component, :b, 2) == %Component{
               state: %{a: 1, b: 2}
             }
    end

    test "nested path, key exists" do
      component = %Component{state: %{a: 1, b: %{d: 4, e: %{g: 6, h: 7}, f: 5}, c: 3}}

      assert put_state(component, [:b, :e, :g], 123) == %Component{
               state: %{a: 1, b: %{d: 4, e: %{g: 123, h: 7}, f: 5}, c: 3}
             }
    end

    test "nested path, key doesn't exist" do
      component = %Component{state: %{a: 1, b: %{d: 4, e: %{g: 6, h: 7}, f: 5}, c: 3}}

      assert put_state(component, [:b, :e, :i], 123) == %Component{
               state: %{a: 1, b: %{d: 4, e: %{g: 6, h: 7, i: 123}, f: 5}, c: 3}
             }
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
