defmodule Hologram.Sync.RulesTest do
  # async: false - the rendered rules are one persistent term for the whole node.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Rules

  alias Hologram.Compiler
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.Rules
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module42

  @cache_key {Rules, :rendered}

  @stale_model_msg "the code changed since the last compile that validated the data model - fix the compile error, if there is one, and save again"

  # A small model stood in for the suite's, whose derived fields only a compile resolves.
  defp put_small_model do
    on_exit(fn ->
      Model.reset_caches()
      Policy.reset_model_facts_cache()
    end)

    put_derived_definitions([Module42])
    Model.put_facts([Module41, Module42], [], nil)
  end

  setup do
    on_exit(fn -> :persistent_term.erase(@cache_key) end)

    :persistent_term.erase(@cache_key)

    :ok
  end

  describe "rendered/0" do
    test "renders the rules of the project's compiled data model" do
      put_small_model()

      assert rendered() == Compiler.render_rules([Module41, Module42])
    end

    test "answers from the cache" do
      :persistent_term.put(@cache_key, "cached rules")

      assert rendered() == "cached rules"
    end

    test "keeps what it rendered for the calls after it" do
      put_small_model()

      rules = rendered()

      assert :persistent_term.get(@cache_key) == rules
    end

    test "raises when the model is under a hold, even when cached" do
      on_exit(&Model.release/0)

      :persistent_term.put(@cache_key, "cached rules")
      Model.hold()

      assert_error Hologram.StaleModelError, @stale_model_msg, fn -> rendered() end
    end
  end

  describe "reset_cache/0" do
    test "drops what was rendered" do
      :persistent_term.put(@cache_key, "cached rules")

      reset_cache()

      assert :persistent_term.get(@cache_key, nil) == nil
    end
  end
end
