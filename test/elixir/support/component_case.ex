defmodule Hologram.Test.ComponentCase do
  use ExUnit.CaseTemplate

  # ExUnit starts a test before Mox has handled the exit of the previous test's process, so Mox can still be in
  # the global mode an earlier test set. Each test starts in private mode, and a test that needs global mode sets
  # it in its own setup, which runs after this one.
  setup {Mox, :set_mox_private}

  using do
    quote do
      import Hologram.Commons.TestUtils
      import Hologram.Template, only: [sigil_HOLO: 2]
      import Hologram.Test.Helpers

      @fixtures_dir "#{File.cwd!()}/test/elixir/support/fixtures"
    end
  end
end
