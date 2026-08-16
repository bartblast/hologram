defmodule Hologram.Sync.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Supervisor

  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Fanout
  alias Hologram.Sync.Pruner
  alias Hologram.Sync.ResultStore

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
               notifications(),
               Dispatcher,
               Pruner
             ]
    end

    test "restarts a child on its own, since one failing says nothing about the others" do
      assert {:ok, {%{strategy: :one_for_one}, _children}} = init([])
    end

    test "finds evaluators by window id" do
      spec = child_spec_of(Evaluator.registry())

      assert {Registry, :start_link, [opts]} = spec.start
      assert opts[:keys] == :unique
      assert opts[:name] == Evaluator.registry()
    end

    test "hears about appends on a connection of its own, outside the pool" do
      spec = child_spec_of(notifications())

      assert {Postgrex.Notifications, :start_link, [opts]} = spec.start
      assert opts[:name] == notifications()
      assert opts[:database]
    end

    # The dispatcher reads the log and has to hand what it reads somewhere - the fanout is what
    # turns a batch of writes into the windows it could have changed.
    test "reads the log into the fanout, listening on the connection beside it" do
      spec = child_spec_of(Dispatcher)

      assert {Dispatcher, :start_link, [opts]} = spec.start
      assert opts[:handler] == (&Fanout.route/1)
      assert opts[:notifications] == notifications()
    end

    test "starts the dispatcher after what it hands work to" do
      ids = child_ids()

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == Evaluators))

      assert Enum.find_index(ids, &(&1 == Dispatcher)) >
               Enum.find_index(ids, &(&1 == Evaluator.registry()))
    end
  end
end
