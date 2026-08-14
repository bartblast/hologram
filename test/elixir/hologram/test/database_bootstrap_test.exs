defmodule Hologram.Test.DatabaseBootstrapTest do
  # async: false - the tests mutate the HOLOGRAM_ENV variable, which is BEAM-global.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.DatabaseBootstrap

  # Only the refusal is tested directly: a passing run!/0 drops the Hologram schemas of
  # the configured database, which is the very database the running suite depends on.
  # The passing path is exercised by every suite boot - test_helper.exs calls it.
  describe "run!/1" do
    setup do
      original = System.get_env("HOLOGRAM_ENV")

      on_exit(fn ->
        if original do
          System.put_env("HOLOGRAM_ENV", original)
        else
          System.delete_env("HOLOGRAM_ENV")
        end
      end)

      :ok
    end

    test "refuses to run outside the test env" do
      System.put_env("HOLOGRAM_ENV", "dev")

      expected_msg =
        "Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's schemas and runs " <>
          "in the test env only - the current env is :dev. When neither " <>
          "HOLOGRAM_ENV nor MIX_ENV is set, the test env is recognized by the " <>
          "running ExUnit server, so call run!/1 after ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run!() end
    end
  end
end
