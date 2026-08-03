defmodule Hologram.ExJsConsistency.Erlang.ElixirConfigTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_config_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "identifier_tokenizer/0" do
    test "names the tokenizer Elixir ships with" do
      assert :elixir_config.identifier_tokenizer() == String.Tokenizer
    end
  end
end
