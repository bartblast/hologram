defmodule Hologram.LiveReload.BroadcasterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.LiveReload.Broadcaster

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
  end

  describe "broadcast_compilation_error/1" do
    test "broadcasts compilation error message with output to hologram_live_reload topic" do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

      error_output = "dummy output"
      assert broadcast_compilation_error(error_output) == :ok

      assert_receive {:compilation_error, ^error_output}
    end
  end

  describe "broadcast_reload/0" do
    test "broadcasts reload message to hologram_live_reload topic" do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

      assert broadcast_reload() == :ok
      assert_receive :reload
    end
  end
end
