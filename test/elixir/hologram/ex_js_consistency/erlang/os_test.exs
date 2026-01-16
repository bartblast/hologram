defmodule Hologram.ExJsConsistency.Erlang.OsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/os_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "type/0" do
    test "returns OS family and OS name" do
      {family, name} = :os.type()
      assert family in [:win32, :unix, :linux] == true
      assert is_atom(name) == true
    end
  end
end
