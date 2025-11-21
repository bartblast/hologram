defmodule Hologram.ExJsConsistency.Erlang.ReTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/re_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "version/0" do
    test "empty string", %{fun: fun} do
      assert :re.version() == ""
    end
  end
end
