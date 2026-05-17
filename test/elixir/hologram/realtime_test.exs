defmodule Hologram.RealtimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime

  alias Hologram.Component.Action
  alias Hologram.Server
  alias Hologram.Server.Broadcast

  describe "broadcast_action/3,4" do
    setup do
      wait_for_process_cleanup(Hologram.PubSub)
      start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

      :ok
    end

    test "broadcasts to the instance channel topic with a custom cid (keyword params)" do
      instance_id = subscribe_to_identity_channel(:instance)

      broadcast_action({:instance, instance_id}, "my_editor", :append_message, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }, []}
    end

    test "accepts params as a map" do
      instance_id = subscribe_to_identity_channel(:instance)

      broadcast_action({:instance, instance_id}, "my_editor", :append_message, %{text: "hi"})

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }, []}
    end

    test "broadcasts to the session channel topic" do
      session_id = subscribe_to_identity_channel(:session)

      broadcast_action({:session, session_id}, "my_editor", :append_message, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }, []}
    end

    test "broadcasts to the user channel topic" do
      user_id = subscribe_to_identity_channel(:user)

      broadcast_action({:user, user_id}, "notifications", :show_toast, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{
                        name: :show_toast,
                        params: %{text: "hi"},
                        target: "notifications"
                      }, []}
    end

    test "supports the no-params arity" do
      instance_id = subscribe_to_identity_channel(:instance)

      broadcast_action({:instance, instance_id}, "layout", :reload_session)

      assert_receive {:broadcast_action,
                      %Action{
                        name: :reload_session,
                        params: %{},
                        target: "layout"
                      }, []}
    end
  end

  describe "broadcast_action_except/4,5" do
    setup do
      wait_for_process_cleanup(Hologram.PubSub)
      start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

      :ok
    end

    # Tests here cover only what's unique to broadcast_action_except: the
    # single-tuple-vs-list dispatch. Channel kinds, cid, and params handling
    # are exercised in the broadcast_action describe block - both functions
    # share the same envelope construction via the private publish/5 helper.

    test "wraps a single identity tuple into a list in the envelope" do
      instance_id = subscribe_to_identity_channel(:instance)
      excluded_identity = {:user, "user-1"}

      broadcast_action_except(excluded_identity, {:instance, instance_id}, "page", :ping)

      assert_receive {:broadcast_action, %Action{name: :ping}, [^excluded_identity]}
    end

    test "passes a list of excluded identities through unchanged" do
      instance_id = subscribe_to_identity_channel(:instance)
      excluded = [{:instance, "other"}, {:session, "session-1"}, {:user, "user-1"}]

      broadcast_action_except(excluded, {:instance, instance_id}, "page", :ping, text: "hi")

      assert_receive {:broadcast_action,
                      %Action{name: :ping, params: %{text: "hi"}, target: "page"}, ^excluded}
    end
  end

  describe "flush_broadcasts/1" do
    setup do
      wait_for_process_cleanup(Hologram.PubSub)
      start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

      :ok
    end

    test "is a no-op for an empty broadcasts list and returns the server unchanged" do
      server = %Server{broadcasts: []}

      assert flush_broadcasts(server) == server
    end

    test "fires queued broadcasts and clears the list" do
      instance_id = subscribe_to_identity_channel(:instance)

      server = %Server{
        broadcasts: [
          %Broadcast{
            channel: {:instance, instance_id},
            cid: "my_editor",
            action_name: :append_message,
            params: %{text: "hi"}
          }
        ]
      }

      result = flush_broadcasts(server)

      assert_receive {:broadcast_action,
                      %Action{
                        name: :append_message,
                        params: %{text: "hi"},
                        target: "my_editor"
                      }, []}

      assert result.broadcasts == []
    end

    test "delivers multiple broadcasts in call order (reverse of the LIFO list)" do
      instance_id = subscribe_to_identity_channel(:instance)

      # broadcasts is LIFO: head is the most recent put_broadcast call.
      # Two calls in order :first, :second produce [%Broadcast{action_name: :second, ...}, %Broadcast{action_name: :first, ...}]
      server = %Server{
        broadcasts: [
          %Broadcast{
            channel: {:instance, instance_id},
            cid: "page",
            action_name: :second,
            params: %{}
          },
          %Broadcast{
            channel: {:instance, instance_id},
            cid: "page",
            action_name: :first,
            params: %{}
          }
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, %Action{name: :first}, []}
      assert_receive {:broadcast_action, %Action{name: :second}, []}
    end
  end
end
