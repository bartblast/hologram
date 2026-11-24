defmodule Mix.Tasks.Holo.Db.ResetTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureIO

  alias Hologram.Reflection
  alias Mix.Tasks.Holo.Db.Reset, as: Task

  setup do
    test_dir =
      Path.join([Reflection.tmp_dir(), "tests", "mix", "tasks", "holo", "db", "reset"])

    clean_dir(test_dir)

    [seeds_path: Path.join(test_dir, "seeds.exs")]
  end

  defp restore_env(name, nil), do: System.delete_env(name)

  defp restore_env(name, value), do: System.put_env(name, value)

  describe "run/1" do
    setup do
      original_env = System.get_env("HOLOGRAM_ENV")
      original_start_flag = System.get_env("HOLOGRAM_START")
      System.delete_env("HOLOGRAM_START")

      on_exit(fn ->
        restore_env("HOLOGRAM_ENV", original_env)
        restore_env("HOLOGRAM_START", original_start_flag)
      end)
    end

    test "refuses every env but dev and test, leaving the start flag unset" do
      System.put_env("HOLOGRAM_ENV", "prod")

      assert_raise Mix.Error,
                   "mix holo.db.reset runs in the dev and test envs only - the current env is :prod",
                   fn -> Task.run([]) end

      assert System.get_env("HOLOGRAM_START") == nil
    end

    # The test run started the app, as an earlier task of an alias would. The refusal of an
    # earlier compile without the start flag can't be staged here, since the started app refuses
    # first.
    test "refuses once an earlier task started the app, leaving the start flag unset" do
      System.put_env("HOLOGRAM_ENV", "dev")

      message =
        "mix holo.db.reset runs in a mix command of its own - an earlier task in this one started the app already, and the reset has to run before the app starts"

      assert_raise Mix.Error, message, fn -> Task.run([]) end

      assert System.get_env("HOLOGRAM_START") == nil
    end
  end

  describe "run_seeds/1" do
    test "runs the seeds file", %{seeds_path: seeds_path} do
      Process.register(self(), :holo_db_reset_test)
      File.write!(seeds_path, "send(:holo_db_reset_test, :seeded)")

      output = capture_io(fn -> assert Task.run_seeds(seeds_path) == :ok end)

      assert_received :seeded
      assert output == "Ran the seeds in #{Path.relative_to_cwd(seeds_path)}\n"
    end

    test "says no seeds ran when there's no seeds file", %{seeds_path: seeds_path} do
      output = capture_io(fn -> assert Task.run_seeds(seeds_path) == :ok end)

      assert output == "No seeds ran - there's no #{Path.relative_to_cwd(seeds_path)}\n"
    end

    test "raises what a seed raises", %{seeds_path: seeds_path} do
      File.write!(seeds_path, ~s[raise ArgumentError, "bad seed"])

      assert_raise ArgumentError, "bad seed", fn -> Task.run_seeds(seeds_path) end
    end
  end
end
