defmodule Mix.Tasks.HoloTest do
  use Hologram.Test.BasicCase, async: false

  setup do
    original_hologram_compile = System.get_env("HOLOGRAM_COMPILE")

    on_exit(fn ->
      if original_hologram_compile do
        System.put_env("HOLOGRAM_COMPILE", original_hologram_compile)
      else
        System.delete_env("HOLOGRAM_COMPILE")
      end
    end)
  end

  describe "run/1" do
    test "sets HOLOGRAM_COMPILE env var to 1" do
      System.delete_env("HOLOGRAM_COMPILE")

      task = Task.async(fn -> Mix.Tasks.Holo.run([]) end)
      Process.sleep(500)

      assert System.get_env("HOLOGRAM_COMPILE") == "1"

      Task.shutdown(task, :brutal_kill)
    end

    test "starts the application" do
      task = Task.async(fn -> Mix.Tasks.Holo.run([]) end)
      Process.sleep(500)

      started_apps = Enum.map(Application.started_applications(), &elem(&1, 0))
      assert :hologram in started_apps

      Task.shutdown(task, :brutal_kill)
    end
  end
end
