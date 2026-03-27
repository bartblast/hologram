defmodule Hologram.Test do
  @doc """
  Starts Hologram for feature/browser tests.

  Runs the Hologram compiler and restarts the application with the full
  supervisor tree. Call this in your `test_helper.exs` before running
  tests that need Hologram pages served in the browser.

      # test_helper.exs
      Hologram.Test.setup()
  """
  def setup do
    System.put_env("HOLOGRAM_START", "1")
    Mix.Tasks.Compile.Hologram.run(force?: true)
    Application.stop(:hologram)
    Application.ensure_all_started(:hologram)
  end
end
