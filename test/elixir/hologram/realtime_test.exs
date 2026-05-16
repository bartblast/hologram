defmodule Hologram.RealtimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime

  alias Hologram.Component.Action

  describe "broadcast_action/3,4" do
    setup do
      wait_for_process_cleanup(Hologram.PubSub)
      start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

      :ok
    end

    test "broadcasts to the instance channel topic with a custom cid" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      topic = "hologram:channel:instance:#{instance_id}"

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      broadcast_action({:instance, instance_id}, "my_editor", :append_message, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }}
    end

    test "broadcasts to the session channel topic" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = "hologram:channel:session:#{session_id}"

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      broadcast_action({:session, session_id}, "my_editor", :append_message, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }}
    end

    test "supports the no-params arity" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      topic = "hologram:channel:instance:#{instance_id}"

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      broadcast_action({:instance, instance_id}, "layout", :reload_session)

      assert_receive {:broadcast_action,
                      %Action{
                        name: :reload_session,
                        params: %{},
                        target: "layout"
                      }}
    end
  end
end
