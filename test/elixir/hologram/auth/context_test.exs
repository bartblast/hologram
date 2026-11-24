defmodule Hologram.Auth.ContextTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth.Context

  # Long enough for a loaded CI runner: a passing test never waits it out.
  @receive_timeout 5_000

  # Runs the function in a spawned process and returns its result.
  defp in_spawned(fun) do
    caller = self()
    ref = make_ref()
    spawn(fn -> send(caller, {ref, fun.()}) end)

    assert_receive {^ref, result}, @receive_timeout

    result
  end

  defp await_down(pid) do
    monitor = Process.monitor(pid)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, @receive_timeout
  end

  defp refused?(fun) do
    fun.()

    false
  rescue
    error in Hologram.MisuseError ->
      assert error.message =~ "started for a request's work"

      true
  end

  # Starts a process that waits for :go, then sends the function's result to report_to.
  defp spawn_waiting(fun, report_to) do
    ref = make_ref()

    pid =
      spawn(fn ->
        receive do
          :go -> send(report_to, {ref, fun.()})
        end
      end)

    {pid, ref}
  end

  test "actor_user_id/0" do
    assert actor_user_id() == nil
  end

  describe "actor_entity_id/0" do
    test "returns nil when no actor is set" do
      assert actor_entity_id() == nil
    end

    test "returns the actor's id when it is a user entity's id" do
      user_id = "0190c4e2-7c1f-7b3a-9d4e-1a2b3c4d5e6f"

      assert with_actor(user_id, fn -> actor_entity_id() end) == user_id
    end

    test "returns nil for an id in any other spelling" do
      for user_id <- ["0190C4E2-7C1F-7B3A-9D4E-1A2B3C4D5E6F", 7, "abc", :admin] do
        assert with_actor(user_id, fn -> actor_entity_id() end) == nil
      end
    end
  end

  describe "put_actor/1" do
    test "sets the actor" do
      put_actor("user_id_9")

      assert actor_user_id() == "user_id_9"
    end

    test "raises Hologram.MisuseError for a boolean, leaving the actor as it was" do
      put_actor("user_id_10")

      assert_error Hologram.MisuseError,
                   "User ID must be a string, integer, or atom other than true and false, but received false",
                   fn ->
                     put_actor(false)
                   end

      assert actor_user_id() == "user_id_10"
    end

    test "sets a signed-out visitor's session for a nil user id" do
      put_actor(nil)

      assert actor_user_id() == nil
      assert session?()
    end
  end

  describe "session?/0" do
    test "is false by default" do
      refute session?()
    end

    test "is true for a user's session" do
      assert with_actor("user_id_12", fn -> session?() end)
    end

    test "is true for a signed-out visitor's session" do
      assert with_actor(nil, fn -> session?() end)
    end

    test "is true for an atom user id" do
      assert with_actor(:admin, fn -> session?() end)
    end

    test "is false again after with_actor/2" do
      with_actor(nil, fn -> :ok end)

      refute session?()
    end

    test "is false again after with_actor/2 raises" do
      assert_raise RuntimeError, fn ->
        with_actor(nil, fn -> raise "error_2" end)
      end

      refute session?()
    end

    test "stays true after a nested call ends" do
      with_actor(nil, fn ->
        with_actor("user_id_13", fn -> :ok end)

        assert session?()
        assert actor_user_id() == nil
      end)
    end

    test "raises Hologram.MisuseError in a process a user's session started" do
      assert with_actor("user_id_54", fn -> in_spawned(fn -> refused?(&session?/0) end) end)
    end

    test "raises Hologram.MisuseError in a process a signed-out visitor's session started" do
      assert with_actor(nil, fn -> in_spawned(fn -> refused?(&session?/0) end) end)
    end

    test "raises Hologram.MisuseError after the starter's session ended on the same process" do
      {pid, ref} =
        with_actor("user_id_55", fn -> spawn_waiting(fn -> refused?(&session?/0) end, self()) end)

      send(pid, :go)

      assert_receive {^ref, true}, @receive_timeout
    end

    test "raises Hologram.MisuseError in a task a supervisor started for a session" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_56", fn ->
               supervisor
               |> Task.Supervisor.async(fn -> refused?(&session?/0) end)
               |> Task.await()
             end)
    end

    test "is false in a process no session started" do
      refute in_spawned(&session?/0)
    end

    test "is false in the session's own process between sessions" do
      with_actor("user_id_57", fn -> :ok end)

      refute session?()
    end

    test "is false inside without_session/1 in a process a session started" do
      refute with_actor("user_id_58", fn ->
               in_spawned(fn -> without_session(&session?/0) end)
             end)
    end

    test "is true for a process a session started that carries the session" do
      fun = with_actor("user_id_59", fn -> capture(&session?/0) end)

      assert with_actor("user_id_60", fn -> in_spawned(fun) end)
    end
  end

  describe "user_id/0" do
    test "returns the session's user id" do
      assert with_actor("user_id_61", fn -> user_id() end) == "user_id_61"
    end

    test "returns nil for a signed-out visitor's session" do
      assert with_actor(nil, fn -> user_id() end) == nil
    end

    test "returns nil with no session" do
      assert user_id() == nil
    end

    test "raises Hologram.MisuseError in a process a session started" do
      assert with_actor("user_id_62", fn -> in_spawned(fn -> refused?(&user_id/0) end) end)
    end
  end

  describe "capture/1" do
    test "runs the function as the user who captured it, in another process" do
      fun = with_actor("user_id_41", fn -> capture(fn -> {actor_user_id(), session?()} end) end)

      assert in_spawned(fun) == {"user_id_41", true}
    end

    test "runs the function as a signed-out visitor when one captured it" do
      fun = with_actor(nil, fn -> capture(fn -> {actor_user_id(), session?()} end) end)

      assert in_spawned(fun) == {nil, true}
    end

    test "runs the function with no session when captured with none" do
      fun = capture(fn -> {actor_user_id(), session?()} end)

      assert in_spawned(fun) == {nil, false}
      assert with_actor("user_id_51", fun) == {nil, false}
    end

    test "runs the function with no session when captured inside without_session/1" do
      fun =
        with_actor("user_id_42", fn ->
          without_session(fn -> capture(fn -> {actor_user_id(), session?()} end) end)
        end)

      assert in_spawned(fun) == {nil, false}
      assert with_actor("user_id_52", fun) == {nil, false}
    end

    # Errs toward refusing: clearing the record when the function ends would leave a task started
    # inside it trusted, and such a task usually makes its first call after the function returned.
    test "leaves a process that ran the function counted as having served a session" do
      supervisor = start_supervised!(Task.Supervisor)
      fun = in_spawned(fn -> with_actor("user_id_53", fn -> capture(fn -> :ok end) end) end)

      refute supervisor
             |> Task.Supervisor.async(&started_by_request?/0)
             |> Task.await()

      fun.()

      assert supervisor
             |> Task.Supervisor.async(&started_by_request?/0)
             |> Task.await()
    end

    test "keeps the user after the capturing process moves to another user's session" do
      test_pid = self()

      fun = with_actor("user_id_43", fn -> capture(fn -> actor_user_id() end) end)

      with_actor("user_id_44", fn ->
        assert in_spawned(fun) == "user_id_43"
        send(test_pid, :checked)
      end)

      assert_received :checked
    end

    test "keeps the user after the capturing process has ended" do
      test_pid = self()

      starter =
        spawn(fn ->
          send(test_pid, {:fun, with_actor("user_id_45", fn -> capture(&actor_user_id/0) end)})
        end)

      assert_receive {:fun, fun}, @receive_timeout
      await_down(starter)

      assert in_spawned(fun) == "user_id_45"
    end

    test "keeps the arity of a one-argument function" do
      fun = with_actor("user_id_46", fn -> capture(fn arg -> {arg, actor_user_id()} end) end)

      assert in_spawned(fn -> fun.(:arg_1) end) == {:arg_1, "user_id_46"}
    end

    test "works as the function of Task.async_stream/3" do
      fun = with_actor("user_id_47", fn -> capture(fn arg -> {arg, actor_user_id()} end) end)

      result =
        [:arg_2]
        |> Task.async_stream(fun)
        |> Enum.to_list()

      assert result == [ok: {:arg_2, "user_id_47"}]
    end

    test "marks what the wrapped function starts" do
      fun =
        with_actor("user_id_48", fn -> capture(fn -> in_spawned(&started_by_request?/0) end) end)

      assert in_spawned(fun)
    end

    test "puts the running process' own session back afterwards" do
      fun = with_actor("user_id_49", fn -> capture(&actor_user_id/0) end)

      with_actor("user_id_50", fn ->
        assert fun.() == "user_id_49"
        assert actor_user_id() == "user_id_50"
      end)
    end

    test "raises Hologram.MisuseError in a process a session started with no session to carry" do
      assert with_actor("user_id_63", fn ->
               in_spawned(fn -> refused?(fn -> capture(fn -> :ok end) end) end)
             end)
    end

    test "raises Hologram.MisuseError for a function of two arguments" do
      assert_error Hologram.MisuseError,
                   ~r/^as_current_user takes a function of no arguments or of one, got: /,
                   fn -> capture(fn _arg_1, _arg_2 -> :ok end) end
    end

    test "raises Hologram.MisuseError for a value that isn't a function" do
      assert_error Hologram.MisuseError,
                   "as_current_user takes a function of no arguments or of one, got: :abc",
                   fn -> capture(:abc) end
    end
  end

  describe "started_by_request?/0" do
    test "is false for a process no session started" do
      refute started_by_request?()
      refute in_spawned(fn -> started_by_request?() end)
    end

    test "is false in the process working for the session" do
      refute with_actor("user_id_17", fn -> started_by_request?() end)
    end

    test "is false inside without_session/1 in a process a session started" do
      refute with_actor("user_id_33", fn ->
               in_spawned(fn -> without_session(&started_by_request?/0) end)
             end)
    end

    test "is true for a process spawned in a session" do
      assert with_actor("user_id_18", fn -> in_spawned(&started_by_request?/0) end)
    end

    test "is true for a process spawned in a signed-out visitor's session" do
      assert with_actor(nil, fn -> in_spawned(&started_by_request?/0) end)
    end

    test "is true for a process spawned after put_actor/1" do
      put_actor("user_id_19")

      assert in_spawned(&started_by_request?/0)
    end

    test "is true for a Task started in a session" do
      assert with_actor("user_id_20", fn ->
               fn -> started_by_request?() end
               |> Task.async()
               |> Task.await()
             end)
    end

    test "is true for a grandchild" do
      assert with_actor("user_id_21", fn ->
               in_spawned(fn -> in_spawned(&started_by_request?/0) end)
             end)
    end

    test "stays true after the starter has ended" do
      test_pid = self()

      starter =
        spawn(fn ->
          with_actor("user_id_22", fn ->
            send(test_pid, {:started, spawn_waiting(&started_by_request?/0, test_pid)})
          end)
        end)

      assert_receive {:started, {pid, ref}}, @receive_timeout
      await_down(starter)

      send(pid, :go)

      assert_receive {^ref, true}, @receive_timeout
    end

    test "stays true after the starter's session has ended on the same process" do
      {pid, ref} =
        with_actor("user_id_23", fn -> spawn_waiting(&started_by_request?/0, self()) end)

      send(pid, :go)

      assert_receive {^ref, true}, @receive_timeout
    end

    test "is false for a process spawned after the session ended on the same process" do
      with_actor("user_id_24", fn -> :ok end)

      refute in_spawned(&started_by_request?/0)
    end

    test "is false for a process spawned inside without_session/1 in a session" do
      refute with_actor("user_id_25", fn ->
               without_session(fn -> in_spawned(&started_by_request?/0) end)
             end)
    end

    test "is true again for a process spawned after without_session/1 ends" do
      assert with_actor("user_id_26", fn ->
               without_session(fn -> :ok end)
               in_spawned(&started_by_request?/0)
             end)
    end

    test "keeps the mark of a marked process after a nested session ends" do
      assert with_actor("user_id_27", fn ->
               in_spawned(fn ->
                 with_actor("user_id_28", fn -> :ok end)

                 started_by_request?()
               end)
             end)
    end

    test "is true for a task a supervisor started for a process in a session" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_29", fn ->
               supervisor
               |> Task.Supervisor.async(fn -> started_by_request?() end)
               |> Task.await()
             end)
    end

    test "is true for a task a supervisor started for a process that served a session earlier" do
      supervisor = start_supervised!(Task.Supervisor)
      with_actor("user_id_30", fn -> :ok end)

      assert supervisor
             |> Task.Supervisor.async(fn -> started_by_request?() end)
             |> Task.await()
    end

    test "is true for a task a supervisor started for a process that has ended" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      caller =
        spawn(fn ->
          {:ok, task} =
            Task.Supervisor.start_child(supervisor, fn ->
              receive do
                :go -> send(test_pid, {ref, started_by_request?()})
              end
            end)

          send(test_pid, {:task, task})
        end)

      assert_receive {:task, task}, @receive_timeout
      await_down(caller)
      send(task, :go)

      assert_receive {^ref, true}, @receive_timeout
    end

    test "is false for a task a supervisor started for a process with no session" do
      supervisor = start_supervised!(Task.Supervisor)

      refute supervisor
             |> Task.Supervisor.async(fn -> started_by_request?() end)
             |> Task.await()
    end

    test "is true for a process a supervised task spawned for a session" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_31", fn ->
               supervisor
               |> Task.Supervisor.async(fn -> in_spawned(&started_by_request?/0) end)
               |> Task.await()
             end)
    end

    test "is false for a plain Task whose starter, with no session, has ended" do
      test_pid = self()
      ref = make_ref()

      starter =
        spawn(fn ->
          {:ok, task} =
            Task.start(fn ->
              receive do
                :go -> send(test_pid, {ref, started_by_request?()})
              end
            end)

          send(test_pid, {:task, task})
        end)

      assert_receive {:task, task}, @receive_timeout
      await_down(starter)
      send(task, :go)

      assert_receive {^ref, false}, @receive_timeout
    end

    test "is true for a Task.start in a session" do
      test_pid = self()
      ref = make_ref()

      with_actor("user_id_34", fn ->
        Task.start(fn -> send(test_pid, {ref, started_by_request?()}) end)
      end)

      assert_receive {^ref, true}, @receive_timeout
    end

    test "is false for a nested Task whose first starter, with no session, has ended" do
      test_pid = self()
      ref = make_ref()

      starter =
        spawn(fn ->
          Task.start(fn ->
            {:ok, inner} =
              Task.start(fn ->
                receive do
                  :go -> send(test_pid, {ref, started_by_request?()})
                end
              end)

            send(test_pid, {:inner, inner})
            Process.sleep(:infinity)
          end)
        end)

      assert_receive {:inner, inner}, @receive_timeout
      await_down(starter)
      send(inner, :go)

      assert_receive {^ref, false}, @receive_timeout
    end

    test "is true for a supervised task of a process a session spawned" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_64", fn ->
               in_spawned(fn ->
                 supervisor
                 |> Task.Supervisor.async(&started_by_request?/0)
                 |> Task.await()
               end)
             end)
    end

    test "is true for a supervised task of a supervised task of a session" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_65", fn ->
               supervisor
               |> Task.Supervisor.async(fn ->
                 supervisor
                 |> Task.Supervisor.async(&started_by_request?/0)
                 |> Task.await()
               end)
               |> Task.await()
             end)
    end

    test "is true for a supervised task a marked process starts inside without_session/1" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_66", fn ->
               in_spawned(fn ->
                 without_session(fn ->
                   supervisor
                   |> Task.Supervisor.async(&started_by_request?/0)
                   |> Task.await()
                 end)
               end)
             end)
    end

    test "is true for a marked process' supervised task that first looks during without_session/1" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_67", fn ->
               in_spawned(fn ->
                 task =
                   Task.Supervisor.async(supervisor, fn ->
                     receive do
                       :look -> started_by_request?()
                     end
                   end)

                 without_session(fn ->
                   send(task.pid, :look)
                   Task.await(task)
                 end)
               end)
             end)
    end

    test "is false for a supervised task of a live caller whose own starter has ended" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      starter =
        spawn(fn ->
          {:ok, poller} =
            Task.start(fn ->
              receive do
                :go ->
                  answer =
                    supervisor
                    |> Task.Supervisor.async(&started_by_request?/0)
                    |> Task.await()

                  send(test_pid, {ref, answer})
              end
            end)

          send(test_pid, {:poller, poller})
        end)

      assert_receive {:poller, poller}, @receive_timeout
      await_down(starter)
      send(poller, :go)

      assert_receive {^ref, false}, @receive_timeout
    end

    test "is false for a supervised task of a live caller whose starter served a session earlier" do
      supervisor = start_supervised!(Task.Supervisor)
      with_actor("user_id_68", fn -> :ok end)

      answer =
        fn ->
          supervisor
          |> Task.Supervisor.async(&started_by_request?/0)
          |> Task.await()
        end
        |> Task.async()
        |> Task.await()

      refute answer
    end

    # Bandit clears the process dictionary between the requests of a keep-alive connection, and a
    # supervised task can first look after that.
    test "is true for a supervised task whose caller's dictionary was cleared after its session" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      caller =
        spawn(fn ->
          {:ok, task} =
            with_actor("user_id_69", fn ->
              Task.Supervisor.start_child(supervisor, fn ->
                receive do
                  :go -> send(test_pid, {ref, started_by_request?()})
                end
              end)
            end)

          Process.get_keys()
          |> Enum.reject(&(&1 in [:"$ancestors", :"$initial_call", :"$process_label"]))
          |> Enum.each(&Process.delete/1)

          send(test_pid, {:task, task})

          receive do
            :end -> :ok
          end
        end)

      assert_receive {:task, task}, @receive_timeout
      send(task, :go)

      assert_receive {^ref, true}, @receive_timeout

      send(caller, :end)
    end

    # Walking a process once per path took minutes at this depth.
    test "answers quickly under deeply nested supervisors" do
      nest = fn nest, depth ->
        if depth == 0 do
          started_by_request?()
        else
          {:ok, supervisor} = Task.Supervisor.start_link()

          supervisor
          |> Task.Supervisor.async(fn -> nest.(nest, depth - 1) end)
          |> Task.await()
        end
      end

      refute nest.(nest, 26)
    end

    test "is true for a process a session's supervised task started inside without_session/1" do
      supervisor = start_supervised!(Task.Supervisor)

      assert with_actor("user_id_35", fn ->
               supervisor
               |> Task.Supervisor.async(fn ->
                 without_session(fn -> in_spawned(&started_by_request?/0) end)
               end)
               |> Task.await()
             end)
    end

    test "is true for a process a task of an ended caller started inside without_session/1" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      caller =
        spawn(fn ->
          {:ok, task} =
            Task.Supervisor.start_child(supervisor, fn ->
              receive do
                :go ->
                  answer = without_session(fn -> in_spawned(&started_by_request?/0) end)
                  send(test_pid, {ref, answer})
              end
            end)

          send(test_pid, {:task, task})
        end)

      assert_receive {:task, task}, @receive_timeout
      await_down(caller)
      send(task, :go)

      assert_receive {^ref, true}, @receive_timeout
    end

    # Reading the task's state at the check would answer false here, and keep it.
    test "stays true for a child that first looks while its supervised task is in without_session/1" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      {:ok, task} =
        with_actor("user_id_40", fn ->
          Task.Supervisor.start_child(supervisor, fn ->
            child =
              spawn(fn ->
                receive do
                  :look -> send(test_pid, {:first, started_by_request?()})
                end

                receive do
                  :look_again -> send(test_pid, {ref, started_by_request?()})
                end
              end)

            without_session(fn ->
              send(child, :look)

              receive do
                :leave -> :ok
              end
            end)

            send(test_pid, {:left, child})

            receive do
              :end -> :ok
            end
          end)
        end)

      assert_receive {:first, true}, @receive_timeout

      send(task, :leave)
      assert_receive {:left, child}, @receive_timeout

      send(child, :look_again)
      assert_receive {^ref, true}, @receive_timeout

      send(task, :end)
    end

    test "is true for a Task.async_stream worker in a session" do
      result =
        with_actor("user_id_37", fn ->
          [1]
          |> Task.async_stream(fn _elem -> started_by_request?() end)
          |> Enum.to_list()
        end)

      assert result == [ok: true]
    end

    test "is false for a Task.async_stream worker of a process that served a session earlier" do
      with_actor("user_id_38", fn -> :ok end)

      result =
        [1]
        |> Task.async_stream(fn _elem -> started_by_request?() end)
        |> Enum.to_list()

      assert result == [ok: false]
    end

    # The supervisor is in the caller's own lineage here, but it was spawned before the session, so
    # it carries no mark and only the caller's record can tell.
    test "is true for a task of a supervisor the process started itself before the session" do
      {:ok, supervisor} = Task.Supervisor.start_link()

      assert with_actor("user_id_39", fn ->
               supervisor
               |> Task.Supervisor.async(fn -> started_by_request?() end)
               |> Task.await()
             end)
    end

    test "keeps an answer of false after the caller serves a session" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      {:ok, task} =
        Task.Supervisor.start_child(supervisor, fn ->
          first = started_by_request?()
          send(test_pid, :looked)

          receive do
            :go -> send(test_pid, {ref, {first, started_by_request?()}})
          end
        end)

      assert_receive :looked, @receive_timeout
      with_actor("user_id_32", fn -> :ok end)
      send(task, :go)

      assert_receive {^ref, {false, false}}, @receive_timeout
    end

    test "keeps an answer of true after the supervised task that started the process ends" do
      supervisor = start_supervised!(Task.Supervisor)
      test_pid = self()
      ref = make_ref()

      with_actor("user_id_36", fn ->
        Task.Supervisor.start_child(supervisor, fn ->
          child =
            spawn(fn ->
              first = started_by_request?()
              send(test_pid, {:looked, self()})

              receive do
                :go -> send(test_pid, {ref, {first, started_by_request?()}})
              end
            end)

          send(test_pid, {:task, self(), child})

          receive do
            :end -> :ok
          end
        end)
      end)

      assert_receive {:task, task, child}, @receive_timeout
      assert_receive {:looked, ^child}, @receive_timeout

      send(task, :end)
      await_down(task)
      send(child, :go)

      assert_receive {^ref, {true, true}}, @receive_timeout
    end
  end

  describe "with_actor/2" do
    test "raises Hologram.MisuseError for a boolean before the function runs, leaving the actor as it was" do
      with_actor("user_id_11", fn ->
        assert_error Hologram.MisuseError,
                     "User ID must be a string, integer, or atom other than true and false, but received true",
                     fn ->
                       with_actor(true, fn -> send(self(), :ran) end)
                     end

        refute_received :ran

        assert actor_user_id() == "user_id_11"
      end)
    end

    test "sets the actor for the duration of the function" do
      assert with_actor("user_id_1", fn -> actor_user_id() end) == "user_id_1"
    end

    test "returns the function result" do
      assert with_actor("user_id_2", fn -> :result_1 end) == :result_1
    end

    test "clears the actor afterwards" do
      with_actor("user_id_3", fn -> :ok end)

      assert actor_user_id() == nil
    end

    test "restores the enclosing actor afterwards" do
      result =
        with_actor("user_id_4", fn ->
          with_actor("user_id_5", fn -> :ok end)

          actor_user_id()
        end)

      assert result == "user_id_4"
    end

    # The session lives in the process dictionary, so work moved off the request process starts
    # with none - and that must not read as the trusted tier.
    test "leaves a spawned process without a session, which session?/0 refuses" do
      spawned_state =
        with_actor("user_id_8", fn ->
          fn -> {actor_user_id(), refused?(&session?/0)} end
          |> Task.async()
          |> Task.await()
        end)

      assert spawned_state == {nil, true}
    end

    test "restores the enclosing actor when the function raises" do
      with_actor("user_id_6", fn ->
        assert_raise RuntimeError, fn ->
          with_actor("user_id_7", fn -> raise "error_1" end)
        end

        assert actor_user_id() == "user_id_6"
      end)

      assert actor_user_id() == nil
    end
  end

  describe "without_session/1" do
    test "runs the function with no session" do
      result =
        with_actor("user_id_14", fn ->
          without_session(fn -> {actor_user_id(), session?()} end)
        end)

      assert result == {nil, false}
    end

    test "returns the function result" do
      assert without_session(fn -> :result_3 end) == :result_3
    end

    test "restores a user's session afterwards" do
      with_actor("user_id_15", fn ->
        without_session(fn -> :ok end)

        assert actor_user_id() == "user_id_15"
      end)
    end

    test "restores a signed-out visitor's session afterwards" do
      with_actor(nil, fn ->
        without_session(fn -> :ok end)

        assert session?()
      end)
    end

    test "restores the session when the function raises" do
      with_actor("user_id_16", fn ->
        assert_raise RuntimeError, fn ->
          without_session(fn -> raise "error_3" end)
        end

        assert actor_user_id() == "user_id_16"
      end)
    end

    test "leaves no session when there was none" do
      without_session(fn -> :ok end)

      refute session?()
    end
  end
end
