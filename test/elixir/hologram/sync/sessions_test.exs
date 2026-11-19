defmodule Hologram.Sync.SessionsTest do
  # async: false - each test starts the session registry under its fixed name, shared by the whole
  # node.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Sessions

  @user_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  setup do
    wait_for_process_cleanup(registry())
    start_supervised!(Hologram.Sync.Sessions)

    :ok
  end

  # Registers a process of its own, which stays until the test ends.
  defp start_session(user_id) do
    test_pid = self()

    pid =
      spawn_link(fn ->
        register(user_id)
        send(test_pid, :registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :registered

    pid
  end

  describe "list/0" do
    test "lists nothing on a node with no sessions" do
      assert list() == []
    end

    test "lists every session with the user it serves, several of one user included" do
      first = start_session(@user_id)
      second = start_session(@user_id)
      anonymous = start_session(nil)

      assert Enum.sort(list()) ==
               Enum.sort([{first, @user_id}, {second, @user_id}, {anonymous, nil}])
    end

    test "lists a user id in another spelling as an anonymous user" do
      session = start_session(String.upcase(@user_id))

      assert list() == [{session, nil}]
    end

    test "leaves out a session that stopped" do
      session = start_session(@user_id)
      ref = Process.monitor(session)

      send(session, :stop)
      assert_receive {:DOWN, ^ref, :process, ^session, _reason}

      wait_until(fn -> list() == [] end)
    end
  end

  describe "register/1" do
    test "adds the calling process" do
      assert register(@user_id) == :ok
      assert list() == [{self(), @user_id}]
    end

    test "refuses a second registration of the same process" do
      register(@user_id)

      assert_raise MatchError, fn -> register(@user_id) end
    end
  end
end
