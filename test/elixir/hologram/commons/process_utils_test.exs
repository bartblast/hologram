defmodule Hologram.Commons.ProcessUtilsTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Commons.ProcessUtils

  @process_name :"process_#{__MODULE__}"

  setup do
    wait_for_process_cleanup(@process_name)
    :ok
  end

  describe "running?/1" do
    test "is running" do
      pid = spawn(fn -> :timer.sleep(10_000) end)
      Process.register(pid, @process_name)

      assert running?(@process_name)

      Process.exit(pid, :kill)
    end

    test "is not running" do
      refute running?(@process_name)
    end
  end
end
