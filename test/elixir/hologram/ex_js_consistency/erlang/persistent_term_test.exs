defmodule Hologram.ExJsConsistency.Erlang.PersistentTermTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/persistent_term_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  alias Hologram.ExJsConsistency.Erlang.PersistentTermTest

  @moduletag :consistency

  describe "get/2" do
    test "key exists" do
      key = {PersistentTermTest, :my_key_1}
      :persistent_term.put(key, 123)

      assert :persistent_term.get(key, 234) == 123
    end

    test "key doesn't exist" do
      key = {PersistentTermTest, :my_key_2}
      assert :persistent_term.get(key, 234) == 234
    end
  end
end
