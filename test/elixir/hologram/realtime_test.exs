defmodule Hologram.RealtimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime

  alias Hologram.Component.Action
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Server
  alias Hologram.Server.Broadcast

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    wait_for_process_cleanup(Tombstone)
    start_supervised!({Tombstone, boot_sync_timeout_ms: 0})

    :ok
  end

  describe "broadcast_action/2,3" do
    test "broadcasts to the instance channel topic with keyword params" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      broadcast_action(channel, :append_message, text: "hi")

      assert_receive {:broadcast_action, ^channel, :append_message, %{text: "hi"}, []}
    end

    test "accepts params as a map" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      broadcast_action(channel, :append_message, %{text: "hi"})

      assert_receive {:broadcast_action, ^channel, :append_message, %{text: "hi"}, []}
    end

    test "broadcasts to the session channel topic" do
      session_id = subscribe_to_identity_channel(:session)
      channel = {:session, session_id}

      broadcast_action(channel, :append_message, text: "hi")

      assert_receive {:broadcast_action, ^channel, :append_message, %{text: "hi"}, []}
    end

    test "broadcasts to the user channel topic" do
      user_id = subscribe_to_identity_channel(:user)
      channel = {:user, user_id}

      broadcast_action(channel, :show_toast, text: "hi")

      assert_receive {:broadcast_action, ^channel, :show_toast, %{text: "hi"}, []}
    end

    test "supports the no-params arity" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      broadcast_action(channel, :reload_session)

      assert_receive {:broadcast_action, ^channel, :reload_session, %{}, []}
    end

    test "raises ArgumentError when channel fails validation" do
      assert_raise ArgumentError, fn ->
        broadcast_action("not-a-valid-channel", :ping)
      end
    end
  end

  describe "broadcast_action_except/3,4" do
    # Tests here cover only what's unique to broadcast_action_except: the
    # single-tuple-vs-list dispatch. Channel kinds and params handling are
    # exercised in the broadcast_action describe block - both functions share
    # the same envelope construction via the private publish/4 helper.

    test "wraps a single identity tuple into a list in the envelope" do
      instance_id = subscribe_to_identity_channel(:instance)
      excluded_identity = {:user, "user-1"}

      broadcast_action_except(excluded_identity, {:instance, instance_id}, :ping)

      assert_receive {:broadcast_action, _channel, :ping, _params, [^excluded_identity]}
    end

    test "passes a list of excluded identities through unchanged" do
      instance_id = subscribe_to_identity_channel(:instance)
      excluded = [{:instance, "other"}, {:session, "session-1"}, {:user, "user-1"}]

      broadcast_action_except(excluded, {:instance, instance_id}, :ping, text: "hi")

      assert_receive {:broadcast_action, _channel, :ping, %{text: "hi"}, ^excluded}
    end
  end

  describe "channel_topic/1" do
    test "encodes a bare-atom channel" do
      assert channel_topic(:notifications) == "hologram:channel:notifications"
    end

    test "encodes a 2-tuple application channel" do
      assert channel_topic({:room, 42}) == "hologram:channel:room:42"
    end

    test "encodes a 3+-tuple application channel" do
      assert channel_topic({:doc, "abc", "v2"}) == "hologram:channel:doc:abc:v2"
    end

    test "encodes an identity-shaped tuple consistently with identity_topic/2" do
      assert channel_topic({:instance, "abc"}) == identity_topic(:instance, "abc")
      assert channel_topic({:session, "s1"}) == identity_topic(:session, "s1")
      assert channel_topic({:user, 7}) == identity_topic(:user, 7)
    end
  end

  describe "flush_broadcasts/1" do
    test "is a no-op for an empty broadcasts list and returns the server unchanged" do
      server = %Server{broadcasts: []}

      assert flush_broadcasts(server) == server
    end

    test "fires queued broadcasts and clears the list" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      server = %Server{
        instance_id: instance_id,
        broadcasts: [
          %Broadcast{
            channel: channel,
            action_name: :append_message,
            params: %{text: "hi"}
          }
        ]
      }

      result = flush_broadcasts(server)

      assert_receive {:broadcast_action, ^channel, :append_message, %{text: "hi"},
                      [{:instance, ^instance_id}]}

      assert result.broadcasts == []
    end

    test "delivers multiple broadcasts in call order (reverse of the LIFO list)" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      # broadcasts is LIFO: head is the most recent put_broadcast call.
      # Two calls in order :first, :second produce entries in :second, :first order.
      server = %Server{
        instance_id: instance_id,
        broadcasts: [
          %Broadcast{channel: channel, action_name: :second, params: %{}},
          %Broadcast{channel: channel, action_name: :first, params: %{}}
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, ^channel, :first, _params, [{:instance, ^instance_id}]}

      assert_receive {:broadcast_action, ^channel, :second, _params, [{:instance, ^instance_id}]}
    end

    test "auto-excludes the originator's instance via excluded_identities" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      server = %Server{
        instance_id: instance_id,
        broadcasts: [
          %Broadcast{channel: channel, action_name: :ping, params: %{}}
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, ^channel, :ping, _params, [{:instance, ^instance_id}]}
    end

    test "merges dev-supplied except identities with the auto-excluded originator instance" do
      instance_id = subscribe_to_identity_channel(:instance)
      channel = {:instance, instance_id}

      server = %Server{
        instance_id: instance_id,
        broadcasts: [
          %Broadcast{
            channel: channel,
            action_name: :ping,
            params: %{},
            except: [{:session, "some-session-id"}]
          }
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, ^channel, :ping, _params, excluded}

      assert Enum.sort(excluded) ==
               Enum.sort([{:instance, instance_id}, {:session, "some-session-id"}])
    end

    test "dedupes auto-excluded originator instance when dev also excluded it explicitly" do
      instance_id = subscribe_to_identity_channel(:instance)
      originator = {:instance, instance_id}
      channel = {:instance, instance_id}

      server = %Server{
        instance_id: instance_id,
        broadcasts: [
          %Broadcast{
            channel: channel,
            action_name: :ping,
            params: %{},
            except: [originator]
          }
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, ^channel, :ping, _params, [^originator]}
    end

    test "fires a queued broadcast on an application channel" do
      topic = channel_topic({:room, 42})
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      server = %Server{
        instance_id: "test-instance",
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append_message,
            params: %{text: "hi"}
          }
        ]
      }

      flush_broadcasts(server)

      assert_receive {:broadcast_action, {:room, 42}, :append_message, %{text: "hi"},
                      [{:instance, "test-instance"}]}
    end
  end

  # TODO: target: "page" placeholder assertions below track the temporary
  # placeholder in `Realtime.get_self_echoes/1`; update when self-echo
  # materialization becomes per-binding (one Action per matching
  # `{channel, cid}` in `server.subscriptions`).
  describe "get_self_echoes/1" do
    test "returns [] when broadcasts list is empty" do
      server = %Server{instance_id: "originator", broadcasts: []}

      assert get_self_echoes(server) == []
    end

    test "includes a put_broadcast targeting a subscribed application channel" do
      server = %Server{
        instance_id: "originator",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"}
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :append, params: %{text: "hi"}, target: "page"}
             ]
    end

    test "excludes a put_broadcast targeting an unsubscribed channel" do
      server = %Server{
        instance_id: "originator",
        subscriptions: [],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"}
          }
        ]
      }

      assert get_self_echoes(server) == []
    end

    test "includes a put_broadcast targeting the originator's auto-subscribed instance channel" do
      server = %Server{
        instance_id: "originator",
        broadcasts: [
          %Broadcast{
            channel: {:instance, "originator"},
            action_name: :ping,
            params: %{}
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :ping, params: %{}, target: "page"}
             ]
    end

    test "includes a put_broadcast targeting the originator's auto-subscribed session channel" do
      server = %Server{
        instance_id: "originator",
        session_id: "session-1",
        broadcasts: [
          %Broadcast{
            channel: {:session, "session-1"},
            action_name: :ping,
            params: %{}
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :ping, params: %{}, target: "page"}
             ]
    end

    test "includes a put_broadcast targeting the originator's auto-subscribed user channel" do
      server = %Server{
        instance_id: "originator",
        session_id: "session-1",
        user_id: "user-1",
        broadcasts: [
          %Broadcast{
            channel: {:user, "user-1"},
            action_name: :ping,
            params: %{}
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :ping, params: %{}, target: "page"}
             ]
    end

    test "excludes a subscribed broadcast when except covers the originator instance" do
      server = %Server{
        instance_id: "originator",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"},
            except: [{:instance, "originator"}]
          }
        ]
      }

      assert get_self_echoes(server) == []
    end

    test "excludes a subscribed broadcast when except covers the originator session" do
      server = %Server{
        instance_id: "originator",
        session_id: "session-1",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"},
            except: [{:session, "session-1"}]
          }
        ]
      }

      assert get_self_echoes(server) == []
    end

    test "excludes a subscribed broadcast when except covers the originator user" do
      server = %Server{
        instance_id: "originator",
        session_id: "session-1",
        user_id: "user-1",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"},
            except: [{:user, "user-1"}]
          }
        ]
      }

      assert get_self_echoes(server) == []
    end

    test "includes a subscribed broadcast when except covers a non-originator identity only" do
      server = %Server{
        instance_id: "originator",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :append,
            params: %{text: "hi"},
            except: [{:instance, "other-instance"}]
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :append, params: %{text: "hi"}, target: "page"}
             ]
    end

    test "preserves call order across multiple self-echoed broadcasts" do
      # The broadcasts list is LIFO: head is the most recent call. get_self_echoes/1
      # walks it in reverse so the returned list matches call order.
      server = %Server{
        instance_id: "originator",
        subscriptions: [{{:room, 42}, "msgs"}],
        broadcasts: [
          %Broadcast{
            channel: {:room, 42},
            action_name: :second,
            params: %{}
          },
          %Broadcast{
            channel: {:room, 42},
            action_name: :first,
            params: %{}
          }
        ]
      }

      assert get_self_echoes(server) == [
               %Action{name: :first, params: %{}, target: "page"},
               %Action{name: :second, params: %{}, target: "page"}
             ]
    end
  end

  describe "maybe_announce_identity_change/2" do
    test "broadcasts on the pre session's announce topic when session_id changes" do
      pre_session_id = setup_session_announce_subscription()
      post_session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      pre = %Server{session_id: pre_session_id, user_id: 7}
      post = %Server{session_id: post_session_id, user_id: 7}

      maybe_announce_identity_change(pre, post)

      assert_receive {:identity_changed, ^post_session_id, 7}
    end

    test "broadcasts on the pre session's announce topic when user_id changes" do
      session_id = setup_session_announce_subscription()
      pre = %Server{session_id: session_id, user_id: nil}
      post = %Server{session_id: session_id, user_id: 7}

      maybe_announce_identity_change(pre, post)

      assert_receive {:identity_changed, ^session_id, 7}
    end

    test "broadcasts post identity when both session_id and user_id change" do
      pre_session_id = setup_session_announce_subscription()
      post_session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      pre = %Server{session_id: pre_session_id, user_id: 7}
      post = %Server{session_id: post_session_id, user_id: 8}

      maybe_announce_identity_change(pre, post)

      assert_receive {:identity_changed, ^post_session_id, 8}
    end

    test "emits no broadcast when nothing changed" do
      session_id = setup_session_announce_subscription()
      server = %Server{session_id: session_id, user_id: 7}

      maybe_announce_identity_change(server, server)

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "emits no broadcast when pre.session_id is nil even if user_id changes" do
      setup_session_announce_subscription()

      pre = %Server{session_id: nil, user_id: nil}
      post = %Server{session_id: nil, user_id: 7}

      maybe_announce_identity_change(pre, post)

      refute_receive {:identity_changed, _session_id, _user_id}
    end
  end

  test "session_announce_topic/1" do
    assert session_announce_topic(42) == "hologram:announce:session:42"
  end

  describe "subscribe/3" do
    test "registers the binding in the registry for the resolved instance" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      SubscriptionRegistry.update_identity("instance-1", "session-1", 7)

      subscribe({:user, 7}, :notifications, "c1")

      assert SubscriptionRegistry.bindings_of("instance-1") == %{{:notifications, "c1"} => 7}
    end

    test "sends a signed receipt via {:add_sub_receipts, ...} to the target SSE process" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      SubscriptionRegistry.update_identity("instance-1", "session-1", 7)

      subscribe({:user, 7}, :notifications, "c1")

      assert_receive {:add_sub_receipts, [{:notifications, "c1", token}]}
      assert {:ok, receipt} = Receipt.verify(token)
      assert receipt.channel == :notifications
      assert receipt.cid == "c1"
      assert receipt.instance_id == "instance-1"
      assert receipt.user_id == 7
    end

    test "fans out to every connection resolved by the identity (multi-tab)" do
      test_pid = self()

      sse_a =
        spawn(fn ->
          receive do
            {:add_sub_receipts, _receipts} = msg -> send(test_pid, {:tab_a, msg})
          end
        end)

      sse_b =
        spawn(fn ->
          receive do
            {:add_sub_receipts, _receipts} = msg -> send(test_pid, {:tab_b, msg})
          end
        end)

      :ok = SubscriptionRegistry.register_connection("instance-a", sse_a)
      :ok = SubscriptionRegistry.register_connection("instance-b", sse_b)
      SubscriptionRegistry.update_identity("instance-a", "session-a", 7)
      SubscriptionRegistry.update_identity("instance-b", "session-b", 7)

      subscribe({:user, 7}, :notifications, "c1")

      assert_receive {:tab_a, {:add_sub_receipts, [{:notifications, "c1", _token_a}]}}
      assert_receive {:tab_b, {:add_sub_receipts, [{:notifications, "c1", _token_b}]}}
    end

    test "tags the binding with the entry's current authorizing_user_id (anonymous stays anonymous)" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      SubscriptionRegistry.update_identity("instance-1", "session-1", nil)

      subscribe({:instance, "instance-1"}, :notifications, "c1")

      assert SubscriptionRegistry.bindings_of("instance-1") == %{{:notifications, "c1"} => nil}
    end

    test "raises ArgumentError on an invalid channel" do
      assert_raise ArgumentError, fn ->
        subscribe({:user, 7}, "string-channel", "c1")
      end
    end

    test "is a no-op when the identity resolves to no live SSE process" do
      assert subscribe({:user, 999}, :notifications, "c1") == :ok

      refute_receive {:add_sub_receipts, _receipts}
      refute_receive {:sub, _channel}
    end

    test "a later-connecting target with the matched identity receives no binding from the no-op subscribe" do
      subscribe({:user, 999}, :notifications, "c1")

      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      SubscriptionRegistry.update_identity("instance-1", "session-1", 999)

      assert SubscriptionRegistry.bindings_of("instance-1") == %{}
    end

    test "gossips both binding-level and channel-wide purges on the tombstone topic for connected targets" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      SubscriptionRegistry.update_identity("instance-1", "session-1", 7)
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, Tombstone.gossip_topic())

      subscribe({:user, 7}, :notifications, "c1")

      assert_receive {:purge, {{:user, 7}, :notifications, "c1"}}
      assert_receive {:purge, {{:user, 7}, :notifications}}
    end

    test "gossips both binding-level and channel-wide purges on the tombstone topic for offline targets" do
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, Tombstone.gossip_topic())

      subscribe({:user, 999}, :notifications, "c1")

      assert_receive {:purge, {{:user, 999}, :notifications, "c1"}}
      assert_receive {:purge, {{:user, 999}, :notifications}}
    end
  end

  describe "unsubscribe/3" do
    test "writes a binding-level tombstone for the identity/channel/cid key" do
      identity = {:user, 7}

      unsubscribe(identity, :notifications, "c1")

      tombstone_key = {identity, :notifications, "c1"}

      assert [{^tombstone_key, _created_at}] =
               :ets.lookup(Tombstone.ets_table_name(), tombstone_key)
    end

    test "broadcasts {:drop_sub_receipts, ...} on the target identity's channel topic" do
      identity = {:user, 7}
      topic = identity_topic(:user, 7)
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      unsubscribe(identity, :notifications, "c1")

      assert_receive {:drop_sub_receipts, [{:notifications, "c1"}]}
    end

    test "raises ArgumentError on an invalid channel" do
      assert_raise ArgumentError, fn ->
        unsubscribe({:user, 7}, "string-channel", "c1")
      end
    end
  end

  describe "unsubscribe_all/2" do
    test "writes a channel-wide tombstone for the identity/channel key" do
      identity = {:user, 7}

      unsubscribe_all(identity, :notifications)

      tombstone_key = {identity, :notifications}

      assert [{^tombstone_key, _created_at}] =
               :ets.lookup(Tombstone.ets_table_name(), tombstone_key)
    end

    test "broadcasts {:drop_channel, channel} on the target identity's channel topic" do
      identity = {:user, 7}
      topic = identity_topic(:user, 7)
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      unsubscribe_all(identity, :notifications)

      assert_receive {:drop_channel, :notifications}
    end

    test "raises ArgumentError on an invalid channel" do
      assert_raise ArgumentError, fn ->
        unsubscribe_all({:user, 7}, "string-channel")
      end
    end
  end
end
