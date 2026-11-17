defmodule Hologram.Sync.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Supervisor

  alias Hologram.DB.Listener
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Live
  alias Hologram.Sync.ReadEdge
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Sessions

  defp child_ids do
    {:ok, {_flags, children}} = init([])

    Enum.map(children, & &1.id)
  end

  defp child_spec_of(id) do
    {:ok, {_flags, children}} = init([])

    Enum.find(children, &(&1.id == id))
  end

  describe "init/1" do
    test "starts what a node needs to keep its clients up to date" do
      assert child_ids() == [
               Evaluator.registry(),
               ResultStore,
               Evaluators,
               ReadEdge,
               Sessions.registry(),
               notifications(),
               Dispatcher
             ]
    end

    # Restarting one of these alone is what nothing here can survive quietly: evaluators left
    # alive by a replaced registry are unfindable rather than dead, so rounds reach nobody and no
    # error is raised anywhere.
    test "restarts a child with everything that depends on it" do
      assert {:ok, {%{strategy: :rest_for_one}, _children}} = init([])
    end

    test "finds evaluators by window id" do
      spec = child_spec_of(Evaluator.registry())

      assert {Registry, :start_link, [opts]} = spec.start
      assert opts[:keys] == :unique
      assert opts[:name] == Evaluator.registry()
    end

    # Each session is its own key, so one leaving is cleared without a scan of every other.
    test "lists the sessions on the node, each under its own key" do
      spec = child_spec_of(Sessions.registry())

      assert {Registry, :start_link, [opts]} = spec.start
      assert opts[:keys] == :unique
      assert opts[:name] == Sessions.registry()
    end

    # A read edge replaced starts the dispatcher at the log's edge as it stands, and a session left
    # running would claim a place past the batches in between. Coming after it is what has every
    # session stopped along with it.
    test "keeps the session list behind the read edge" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == Sessions.registry())) >
               Enum.find_index(ids, &(&1 == ReadEdge))
    end

    test "hears about appends on a connection of its own, outside the pool" do
      spec = child_spec_of(notifications())

      assert {Listener, :start_link, [opts]} = spec.start
      assert opts[:name] == notifications()
    end

    # The dispatcher reads the log and has to hand what it reads somewhere - the live router is
    # what turns a batch of writes into what it means for each session, and the windows it could
    # have changed.
    test "reads the log into the live router, listening on the connection beside it" do
      spec = child_spec_of(Dispatcher)

      assert {Dispatcher, :start_link, [opts]} = spec.start
      assert opts[:handler] == (&Live.route/2)
      assert opts[:notifications] == notifications()
    end

    # Nothing before the dispatcher is restarted when the dispatcher crashes, and sessions are not
    # in this tree at all - so it comes back beside the same sessions, still advancing from the
    # rounds it sends. Where it had read to has to outlive it for that to be safe, which is why it
    # is kept as a read edge rather than in the state that died with it.
    test "keeps where the log has been read outside the process reading it" do
      spec = child_spec_of(Dispatcher)

      assert {Dispatcher, :start_link, [opts]} = spec.start
      assert opts[:read_edge] == ReadEdge
    end

    test "starts the dispatcher after what it hands work to" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == Evaluators))

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == Evaluator.registry()))

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == Sessions.registry()))
    end

    # A dispatcher restarting reads the edge to resume from, which it can only do if what keeps it
    # is already up.
    test "starts the dispatcher after the read edge it resumes from" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == Dispatcher)) > Enum.find_index(ids, &(&1 == ReadEdge))
    end

    # The dispatcher listens once, at its own start. A replaced connection would leave it listening
    # to a process that no longer exists - it would fall back to its poll and be quietly slower for
    # as long as the node ran. Coming after is what has it restart and listen again.
    test "starts the dispatcher after the connection it listens on" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == notifications()))
    end

    # The other side of that: restarting the connection restarts the dispatcher, and a dispatcher
    # coming back has to find the edge it had reached still kept. Behind the connection it would be
    # replaced along with it, and every reconnection of a listener would cost a skipped window.
    test "keeps the read edge ahead of what a restart of the dispatcher follows from" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == ReadEdge)) <
               Enum.find_index(ids, &(&1 == notifications()))
    end
  end
end
