defmodule Hologram.Sync.FinalSeqTest do
  # Not async: the published limit is one for the whole node.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.FinalSeq

  alias Hologram.DB.Connection

  # Runs the function in a process of its own marked as a test's sandbox, as the database case
  # marks the test process.
  defp sandboxed(fun) do
    fn ->
      Connection.enter_sandbox()
      fun.()
    end
    |> Task.async()
    |> Task.await()
  end

  setup do
    published_before = current()
    on_exit(fn -> publish(published_before) end)
  end

  describe "all_final/0" do
    test "is the highest bigint" do
      assert all_final() == 9_223_372_036_854_775_807
    end
  end

  describe "current/0" do
    test "returns the published limit" do
      :ok = publish(4_216)

      assert current() == 4_216
    end

    test "returns the published limit in every process" do
      :ok = publish(4_216)

      task = Task.async(fn -> current() end)

      assert Task.await(task) == 4_216
    end

    test "returns the pinned limit while a pin is set" do
      :ok = publish(4_216)

      assert with_pinned(17, fn -> current() end) == 17
    end

    test "reads every number as final in a test's sandbox" do
      :ok = publish(4_216)

      assert sandboxed(fn -> current() end) == all_final()
    end

    test "returns the pinned limit in a test's sandbox" do
      assert sandboxed(fn -> with_pinned(17, fn -> current() end) end) == 17
    end
  end

  describe "publish/1" do
    test "replaces the published limit" do
      :ok = publish(4_216)
      :ok = publish(4_217)

      assert current() == 4_217
    end

    test "publishes a limit nothing is final below" do
      :ok = publish(4_216)
      :ok = publish(0)

      assert current() == 0
    end
  end

  describe "with_pinned/1" do
    test "pins the limit published when it starts" do
      :ok = publish(4_216)

      assert with_pinned(fn ->
               :ok = publish(4_217)
               current()
             end) == 4_216
    end

    test "keeps a pin already set" do
      :ok = publish(4_216)

      assert with_pinned(17, fn -> with_pinned(fn -> current() end) end) == 17
    end
  end

  describe "with_pinned/2" do
    test "returns what the function returns" do
      assert with_pinned(17, fn -> :done end) == :done
    end

    test "restores the published limit once the function returns" do
      :ok = publish(4_216)

      with_pinned(17, fn -> :done end)

      assert current() == 4_216
    end

    test "restores the pin it replaced once the function returns" do
      assert with_pinned(17, fn ->
               with_pinned(18, fn -> :done end)
               current()
             end) == 17
    end

    test "restores the published limit once the function raises" do
      :ok = publish(4_216)

      assert_raise RuntimeError, fn -> with_pinned(17, fn -> raise "failed" end) end

      assert current() == 4_216
    end
  end
end
