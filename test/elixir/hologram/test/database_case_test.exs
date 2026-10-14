defmodule Hologram.Test.DatabaseCaseTest do
  # The case template's tag, which is how a run tells the tests that need a database server
  # from the ones that do not. A module of this case without the tag would run where no
  # server is, and one with it is left out of the runs that have none.
  #
  # async: true - the test reads its own context and nothing else.
  use Hologram.Test.DatabaseCase, async: true

  test "tags every module of the case as a database test", context do
    assert context.database == true
  end
end
