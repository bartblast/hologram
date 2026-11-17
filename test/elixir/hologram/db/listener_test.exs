defmodule Hologram.DB.ListenerTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog

  alias Hologram.DB.Config
  alias Hologram.DB.Listener
  alias Hologram.Test.TCPProxy

  # What a run selects the database tests by: they are the ones that need a server.
  @moduletag :database

  # Short enough for a test to sit through several tries.
  @backoff_ms 50

  defp channel, do: "hologram_listener_test_#{System.unique_integer([:positive])}"

  # A connection of its own, outside the sandboxed pool, whose transaction never commits - and a
  # notification is delivered only once the transaction sending it commits.
  defp notify(channel, payload) do
    {:ok, notifier} =
      [pool_size: 1]
      |> Config.connection_opts()
      |> Postgrex.start_link()

    Postgrex.query!(notifier, "SELECT pg_notify($1, $2)", [channel, payload])

    GenServer.stop(notifier)
  end

  # A notification sent before the LISTEN reaches the server is not delivered, so it is sent until
  # one is.
  defp assert_notified(listener, ref, channel) do
    wait_until(fn ->
      notify(channel, "payload")

      receive do
        {:notification, ^listener, ^ref, ^channel, "payload"} -> true
      after
        50 -> false
      end
    end)
  end

  defp listener_state(listener) do
    {_state_name, %{state: {Listener, state}}} = :sys.get_state(listener)

    state
  end

  defp start_listener(opts) do
    opts = Keyword.put_new(opts, :reconnect_backoff, @backoff_ms)

    start_supervised!(
      Supervisor.child_spec({Listener, opts}, id: make_ref(), restart: :temporary)
    )
  end

  # Started behind a proxy that refuses connections until the test opens it. Each try logs, so a
  # test that leaves it refusing stops it inside its log capture.
  defp start_refused_listener(opts \\ []) do
    proxy = start_proxy()

    {proxy, start_listener(Keyword.put(opts, :port, TCPProxy.port(proxy)))}
  end

  defp start_connected_listener(opts \\ []) do
    start_listener(Keyword.put(opts, :sync_connect, true))
  end

  defp start_proxy do
    start_supervised!(Supervisor.child_spec(TCPProxy, id: make_ref()))
  end

  describe "child_spec/1" do
    test "is named after the connection" do
      assert %{id: :my_listener, start: {Listener, :start_link, [[name: :my_listener]]}} =
               Listener.child_spec(name: :my_listener)
    end
  end

  describe "listen/2" do
    test "delivers the notifications of the channel once the server listens" do
      listener = start_connected_listener()
      channel = channel()

      assert {:ok, ref} = Listener.listen(listener, channel)

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000
    end

    test "delivers each notification to every process listening on the channel" do
      listener = start_connected_listener()
      channel = channel()
      test_pid = self()

      spawn_link(fn ->
        {:ok, ref} = Listener.listen(listener, channel)
        send(test_pid, {:listening, ref})

        receive do
          message -> send(test_pid, {:other_got, message})
        end
      end)

      assert_receive {:listening, other_ref}
      assert {:ok, ref} = Listener.listen(listener, channel)

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000

      assert_receive {:other_got, {:notification, ^listener, ^other_ref, ^channel, "payload"}},
                     2_000
    end

    # What the dispatcher listens through, until it moves to listen/2.
    test "answers the call Postgrex.Notifications.listen/2 makes" do
      listener = start_connected_listener()
      channel = channel()

      assert {:ok, ref} = Postgrex.Notifications.listen(listener, channel)

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000
    end

    test "quotes the channel name" do
      listener = start_connected_listener()
      channel = ~s(#{channel()} "Quoted")

      assert {:ok, ref} = Listener.listen(listener, channel)

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000
    end

    test "forgets a process that exits, and goes on delivering to the others" do
      listener = start_connected_listener()
      channel = channel()
      other_channel = channel()

      task =
        Task.async(fn ->
          {:ok, _ref} = Listener.listen(listener, channel)
          {:ok, _ref} = Listener.listen(listener, other_channel)
        end)

      Task.await(task)

      assert {:ok, ref} = Listener.listen(listener, channel)

      wait_until(fn -> listener_state(listener).refs == %{ref => channel} end)
      assert listener_state(listener).channels == %{channel => %{ref => self()}}

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000
    end

    # A restarted dispatcher listens again on the channel its predecessor listened on.
    test "delivers to a process listening on a channel whose last listener exited" do
      listener = start_connected_listener()
      channel = channel()

      task = Task.async(fn -> Listener.listen(listener, channel) end)
      assert {:ok, _ref} = Task.await(task)
      wait_until(fn -> listener_state(listener).refs == %{} end)

      assert {:ok, ref} = Listener.listen(listener, channel)

      notify(channel, "payload")

      assert_receive {:notification, ^listener, ^ref, ^channel, "payload"}, 2_000
    end

    test "raises for a channel name the server would not listen on as given" do
      listener = start_connected_listener()

      assert_raise ArgumentError, "a channel name cannot be empty", fn ->
        Listener.listen(listener, "")
      end

      assert_raise ArgumentError, ~r/cannot contain null bytes/, fn ->
        Listener.listen(listener, "a" <> <<0>>)
      end

      assert_raise ArgumentError, ~r/cannot exceed 63 bytes, got 64 bytes/, fn ->
        Listener.listen(listener, String.duplicate("a", 64))
      end

      assert {:ok, _ref} = Listener.listen(listener, String.duplicate("a", 63))
    end

    test "answers :eventually while the database refuses connections" do
      capture_log(fn ->
        {_proxy, listener} = start_refused_listener()

        assert {:eventually, _ref} = Listener.listen(listener, channel())

        :gen_statem.stop(listener)
      end)
    end
  end

  describe "while the database refuses connections" do
    test "keeps trying rather than ending" do
      capture_log(fn ->
        {_proxy, listener} = start_refused_listener()
        ref = Process.monitor(listener)

        refute_receive {:DOWN, ^ref, :process, ^listener, _reason}, 10 * @backoff_ms

        :gen_statem.stop(listener)
      end)
    end

    # The dispatcher crashes on each round it cannot read while the database is away, and its
    # listening on the channel ends with it.
    test "stays up when a process listening meanwhile exits" do
      capture_log(fn ->
        {_proxy, listener} = start_refused_listener()
        ref = Process.monitor(listener)

        task = Task.async(fn -> Listener.listen(listener, channel()) end)
        assert {:eventually, _listen_ref} = Task.await(task)

        refute_receive {:DOWN, ^ref, :process, ^listener, _reason}, 10 * @backoff_ms

        :gen_statem.stop(listener)
      end)
    end

    test "listens for a process that listened after another one exited, once the database is reachable" do
      capture_log(fn ->
        {proxy, listener} = start_refused_listener()
        channel = channel()

        task = Task.async(fn -> Listener.listen(listener, channel) end)
        assert {:eventually, _ref} = Task.await(task)
        wait_until(fn -> listener_state(listener).refs == %{} end)

        assert {:eventually, ref} = Listener.listen(listener, channel)

        TCPProxy.open(proxy)

        assert_notified(listener, ref, channel)
      end)
    end

    test "listens on the channels registered meanwhile once the database is reachable" do
      capture_log(fn ->
        {proxy, listener} = start_refused_listener()
        channel = channel()

        assert {:eventually, ref} = Listener.listen(listener, channel)

        TCPProxy.open(proxy)

        assert_notified(listener, ref, channel)
      end)
    end
  end

  describe "handle_result/2" do
    # A LISTEN the server refused would leave the connection up and deaf to that channel.
    test "raises the error of a statement the server refused" do
      error = %Postgrex.Error{message: "refused"}
      {:ok, state} = Listener.init(nil)

      assert_raise Postgrex.Error, "refused", fn -> Listener.handle_result(error, state) end
    end
  end

  describe "a lost session" do
    test "ends the connection rather than reconnecting it" do
      proxy = start_proxy()
      TCPProxy.open(proxy)
      listener = start_connected_listener(port: TCPProxy.port(proxy))
      ref = Process.monitor(listener)

      log =
        capture_log(fn ->
          TCPProxy.close_all(proxy)

          assert_receive {:DOWN, ^ref, :process, ^listener, {:shutdown, :connection_lost}}, 2_000
        end)

      assert log =~ "lost its connection to the database"
    end

    # Nothing calls the connection after it connects, so only the ping it arms itself notices.
    test "is noticed when the link goes silent with nothing in flight" do
      proxy = start_proxy()
      TCPProxy.open(proxy)

      listener =
        start_connected_listener(
          port: TCPProxy.port(proxy),
          idle_interval: 100,
          ping_timeout: 100
        )

      ref = Process.monitor(listener)

      capture_log(fn ->
        TCPProxy.freeze(proxy)

        assert_receive {:DOWN, ^ref, :process, ^listener, {:shutdown, :connection_lost}}, 2_000
      end)
    end
  end

  # Postgrex waits for an answer with no bound of its own, and the connection does nothing else
  # meanwhile - a silent link would hold it, and every process listening through it, for good.
  describe "a LISTEN the server leaves unanswered" do
    # Killed rather than the call timing out, which is what has a rest_for_one supervisor restart
    # the caller with the connection, once, rather than on its own first.
    test "ends the connection before the caller gives up, and the caller with it" do
      proxy = start_proxy()
      TCPProxy.open(proxy)
      listener = start_connected_listener(port: TCPProxy.port(proxy))
      listener_ref = Process.monitor(listener)

      TCPProxy.freeze(proxy)

      {caller, caller_ref} = spawn_monitor(fn -> Listener.listen(listener, channel()) end)

      assert_receive {:DOWN, ^listener_ref, :process, ^listener, :killed}, 6_000
      assert_receive {:DOWN, ^caller_ref, :process, ^caller, {:killed, _call}}, 1_000
    end

    # Nobody waits on the channels sent again as the session opens, so nothing else would notice.
    test "ends the connection when it is the replay sent as the session opens" do
      {:ok, initial_state} = Listener.init(nil)
      state = %{initial_state | channels: %{channel() => %{make_ref() => self()}}}

      {pid, ref} =
        spawn_monitor(fn ->
          {:query, _statement, _state} = Listener.handle_connect(state)

          Process.sleep(:infinity)
        end)

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 6_000
    end

    test "leaves the connection up once the server answers" do
      listener = start_connected_listener([])
      ref = Process.monitor(listener)

      assert {:ok, _listen_ref} = Listener.listen(listener, channel())

      refute_receive {:DOWN, ^ref, :process, ^listener, _reason}, 4_500
    end
  end
end
