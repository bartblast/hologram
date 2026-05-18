defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Component

  alias Hologram.Component
  alias Hologram.Component.Action
  alias Hologram.Component.Command
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Server.Broadcast
  alias Hologram.Test.Fixtures.Component.Module1
  alias Hologram.Test.Fixtures.Component.Module2
  alias Hologram.Test.Fixtures.Component.Module3
  alias Hologram.Test.Fixtures.Component.Module4
  alias Hologram.Test.Fixtures.Component.Module5

  @server %Server{cid: "page"}

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

  describe "delete_subscription/2" do
    test "removes {channel, server.cid} from server.subscriptions" do
      result =
        @server
        |> put_subscription(:room_a)
        |> delete_subscription(:room_a)

      assert result.subscriptions == []
    end

    test "leaves bindings for other cids intact (encapsulation)" do
      server_with_layout_binding = %{@server | subscriptions: [{:room_a, "layout"}]}

      result = delete_subscription(server_with_layout_binding, :room_a)

      assert result.subscriptions == [{:room_a, "layout"}]
    end

    test "records :delete in subscription_ops keyed by {channel, server.cid}" do
      result = delete_subscription(@server, :room_a)

      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :delete}
    end

    test "records :delete even when {channel, cid} is not present in server.subscriptions" do
      result = delete_subscription(@server, :room_a)

      assert result.subscriptions == []
      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :delete}
    end

    test "raises ArgumentError for an invalid channel" do
      assert_raise ArgumentError, fn -> delete_subscription(@server, "not_a_valid_channel") end
    end
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

  describe "maybe_register_colocated_template_markup/1" do
    test "valid template path" do
      template_path = "#{@fixtures_dir}/component/template_7.holo"

      assert maybe_register_colocated_template_markup(template_path) ==
               {:@, [context: Hologram.Component, imports: [{1, Kernel}]],
                [
                  {:__colocated_template_markup__, [context: Hologram.Component],
                   ["My template 7"]}
                ]}
    end

    test "invalid template path" do
      refute maybe_register_colocated_template_markup("/my_invalid_template_path.holo")
    end
  end

  describe "put_action/2, component struct" do
    test "name" do
      result = put_action(%Component{}, :my_action)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_action(%Component{}, name: :my_action)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_action(%Component{}, params: [a: 1, b: 2])

      assert result == %Component{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_action(%Component{}, target: "my_target")

      assert result == %Component{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end

    test "spec: delay" do
      result = put_action(%Component{}, delay: 500)

      assert result == %Component{
               next_action: %Action{name: nil, params: %{}, target: nil, delay: 500}
             }
    end

    test "spec: name, params, target, delay" do
      result =
        put_action(%Component{},
          name: :my_action,
          params: [a: 1, b: 2],
          target: "my_target",
          delay: 500
        )

      assert result == %Component{
               next_action: %Action{
                 name: :my_action,
                 params: %{a: 1, b: 2},
                 target: "my_target",
                 delay: 500
               }
             }
    end
  end

  describe "put_action/2, server struct" do
    test "name" do
      result = put_action(%Server{}, :my_action)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_action(%Server{}, name: :my_action)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_action(%Server{}, params: [a: 1, b: 2])

      assert result == %Server{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_action(%Server{}, target: "my_target")

      assert result == %Server{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end

    test "spec: delay" do
      result = put_action(%Server{}, delay: 750)

      assert result == %Server{
               next_action: %Action{name: nil, params: %{}, target: nil, delay: 750}
             }
    end

    test "spec: name, params, target, delay" do
      result =
        put_action(%Server{},
          name: :my_action,
          params: [a: 1, b: 2],
          target: "my_target",
          delay: 750
        )

      assert result == %Server{
               next_action: %Action{
                 name: :my_action,
                 params: %{a: 1, b: 2},
                 target: "my_target",
                 delay: 750
               }
             }
    end
  end

  describe "put_action/3, component struct" do
    test "accepts params as keyword list" do
      result = put_action(%Component{}, :my_action, a: 1, b: 2)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_action(%Component{}, :my_action, %{a: 1, b: 2})

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end
  end

  describe "put_action/3, server struct" do
    test "accepts params as keyword list" do
      result = put_action(%Server{}, :my_action, a: 1, b: 2)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_action(%Server{}, :my_action, %{a: 1, b: 2})

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end
  end

  describe "put_broadcast/* (common behavior)" do
    test "prepends so multiple calls accumulate in reverse-of-call order" do
      result =
        @server
        |> put_broadcast({:room, 1}, :first)
        |> put_broadcast({:room, 2}, :second)

      assert result.broadcasts == [
               %Broadcast{channel: {:room, 2}, cid: "page", action_name: :second, params: %{}},
               %Broadcast{channel: {:room, 1}, cid: "page", action_name: :first, params: %{}}
             ]
    end

    test "raises at the call site when the channel is invalid" do
      assert_error ArgumentError,
                   "channel must be a bare atom or tagged tuple; got bare string \"bad-channel\"",
                   fn -> put_broadcast(@server, "bad-channel", :foo) end
    end
  end

  describe "put_broadcast/3" do
    test "defaults params to an empty map and uses server.cid as the broadcast target" do
      server = %Server{cid: "layout"}
      result = put_broadcast(server, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{channel: {:room, 42}, cid: "layout", action_name: :refresh, params: %{}}
             ]
    end
  end

  describe "put_broadcast/4" do
    test "defaulted-cid form appends with keyword params and uses server.cid" do
      result = put_broadcast(@server, {:room, 42}, :append_message, text: "hi")

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "page",
                 action_name: :append_message,
                 params: %{text: "hi"}
               }
             ]
    end

    test "defaulted-cid form accepts params as a map" do
      result = put_broadcast(@server, {:room, 42}, :append_message, %{text: "hi"})

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "page",
                 action_name: :append_message,
                 params: %{text: "hi"}
               }
             ]
    end

    test "explicit-cid form overrides server.cid" do
      result = put_broadcast(@server, {:room, 42}, "my_editor", :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :refresh,
                 params: %{}
               }
             ]
    end

    test "guard dispatches by position-3 type (string -> cid, atom -> action_name)" do
      # Position 3 is a binary -> explicit-cid clause; param 4 is the action_name atom.
      cid_form_result = put_broadcast(@server, {:room, 42}, "my_editor", :refresh)

      # Position 3 is an atom -> defaulted-cid clause; param 4 is params.
      action_form_result = put_broadcast(@server, {:room, 42}, :refresh, text: "hi")

      assert cid_form_result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :refresh,
                 params: %{}
               }
             ]

      assert action_form_result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "page",
                 action_name: :refresh,
                 params: %{text: "hi"}
               }
             ]
    end
  end

  describe "put_broadcast/5" do
    test "explicit-cid form overrides server.cid and accepts params" do
      result =
        put_broadcast(@server, {:room, 42}, "my_editor", :append_message, text: "hi")

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :append_message,
                 params: %{text: "hi"}
               }
             ]
    end
  end

  describe "put_broadcast_except/* (common behavior)" do
    # Tests here cover what's shared across all put_broadcast_except arities:
    # the single-tuple-vs-list normalization on except, and validator wiring.
    # Per-arity tests below focus on the cid / params dispatch surface.

    test "wraps a single identity tuple into a list and stores on except" do
      result = put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "page",
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]
    end

    test "stores a list of identities unchanged on except" do
      except = [{:user, "u1"}, {:session, "s1"}, {:instance, "i1"}]

      result = put_broadcast_except(@server, except, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "page",
                 action_name: :refresh,
                 params: %{},
                 except: except
               }
             ]
    end

    test "raises at the call site when the channel is invalid" do
      assert_error ArgumentError,
                   "channel must be a bare atom or tagged tuple; got bare string \"bad-channel\"",
                   fn -> put_broadcast_except(@server, {:user, "u1"}, "bad-channel", :foo) end
    end
  end

  describe "put_broadcast_except/4" do
    test "defaults params to an empty map and uses server.cid as the broadcast target" do
      server = %Server{cid: "my_editor"}
      result = put_broadcast_except(server, {:user, "u1"}, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]
    end
  end

  describe "put_broadcast_except/5" do
    test "defaulted-cid form appends with keyword params and uses server.cid" do
      server = %Server{cid: "my_editor"}

      result =
        put_broadcast_except(server, {:user, "u1"}, {:room, 42}, :append_message, text: "hi")

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :append_message,
                 params: %{text: "hi"},
                 except: [{:user, "u1"}]
               }
             ]
    end

    test "explicit-cid form overrides server.cid" do
      result = put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, "my_editor", :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]
    end

    test "guard dispatches by position-4 type (string -> cid, atom -> action_name)" do
      server = %Server{cid: "layout"}

      # Position 4 is a binary -> explicit-cid clause; param 5 is the action_name atom.
      cid_form_result =
        put_broadcast_except(server, {:user, "u1"}, {:room, 42}, "my_editor", :refresh)

      # Position 4 is an atom -> defaulted-cid clause; param 5 is params.
      action_form_result =
        put_broadcast_except(server, {:user, "u1"}, {:room, 42}, :refresh, text: "hi")

      assert cid_form_result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]

      assert action_form_result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "layout",
                 action_name: :refresh,
                 params: %{text: "hi"},
                 except: [{:user, "u1"}]
               }
             ]
    end
  end

  describe "put_broadcast_except/6" do
    test "explicit-cid form overrides server.cid and accepts params" do
      result =
        put_broadcast_except(
          @server,
          {:user, "u1"},
          {:room, 42},
          "my_editor",
          :append_message,
          text: "hi"
        )

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 cid: "my_editor",
                 action_name: :append_message,
                 params: %{text: "hi"},
                 except: [{:user, "u1"}]
               }
             ]
    end
  end

  describe "put_command/2" do
    test "name" do
      result = put_command(%Component{}, :my_command)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_command(%Component{}, name: :my_command)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_command(%Component{}, params: [a: 1, b: 2])

      assert result == %Component{
               next_command: %Command{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_command(%Component{}, target: "my_target")

      assert result == %Component{
               next_command: %Command{name: nil, target: "my_target", params: %{}}
             }
    end
  end

  describe "put_command/3" do
    test "accepts params as keyword list" do
      result = put_command(%Component{}, :my_command, a: 1, b: 2)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_command(%Component{}, :my_command, %{a: 1, b: 2})

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{a: 1, b: 2}, target: nil}
             }
    end
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
      component = %Component{state: %{a: 1, b: 2}}
      result = put_state(component, :b, 3)

      assert result == %Component{
               state: %{a: 1, b: 3}
             }
    end

    test "nested path, map" do
      component = %Component{state: %{a: 1, b: %{c: 2, d: 3}}}
      result = put_state(component, [:b, :d], 4)

      assert result == %Component{state: %{a: 1, b: %{c: 2, d: 4}}}
    end

    test "nested path, struct" do
      component = %Component{state: %{a: 1, b: %Module5{x: 2, y: 3}}}
      result = put_state(component, [:b, :y], 4)

      assert result == %Component{state: %{a: 1, b: %Module5{x: 2, y: 4}}}
    end
  end

  describe "put_subscription/2" do
    test "appends {channel, server.cid} to server.subscriptions" do
      result = put_subscription(@server, :room_a)

      assert result.subscriptions == [{:room_a, "page"}]
    end

    test "records :put in subscription_ops keyed by {channel, server.cid}" do
      result = put_subscription(@server, :room_a)

      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :put}
    end

    test "server.subscriptions and __meta__.subscription_ops stay in sync across multiple calls" do
      result =
        @server
        |> put_subscription(:room_a)
        |> put_subscription(:room_b)

      assert MapSet.new(result.subscriptions) ==
               MapSet.new([{:room_a, "page"}, {:room_b, "page"}])

      assert result.__meta__.subscription_ops == %{
               {:room_a, "page"} => :put,
               {:room_b, "page"} => :put
             }
    end

    test "deduplicates when the same {channel, cid} key is put again" do
      result =
        @server
        |> put_subscription(:room_a)
        |> put_subscription(:room_a)

      assert result.subscriptions == [{:room_a, "page"}]
      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :put}
    end

    test "raises ArgumentError for an invalid channel" do
      assert_raise ArgumentError, fn -> put_subscription(@server, "not_a_valid_channel") end
    end
  end

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      result = Module3.template().(%{})

      assert [
               {:text, text},
               {:component, Hologram.UI.Link,
                [{"to", [expression: {Hologram.Test.Fixtures.Component.Module6}]}],
                [text: "Module6"]}
             ] = result

      assert normalize_newlines(text) == "Module3 template\n"
    end
  end
end
