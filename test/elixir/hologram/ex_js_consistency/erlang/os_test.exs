defmodule Hologram.ExJsConsistency.Erlang.OsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/os_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "type/0" do
    test "returns OS family and OS name as atoms" do
      {family, type} = :os.type()
      assert family in [:unix, :win32] == true
      assert type in [:darwin, :nt] == true
    end
  end
end
