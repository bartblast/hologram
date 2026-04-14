defmodule Hologram.ExJsConsistency.Elixir.ApplicationTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/application_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "get_env/3" do
    test "returns value when app env is set" do
      Application.put_env(:my_app, :my_key, 42)

      assert Application.get_env(:my_app, :my_key, nil) == 42
    after
      Application.delete_env(:my_app, :my_key)
    end

    test "returns default when app is not set" do
      assert Application.get_env(:my_app_not_set, :my_key, :default) == :default
    end

    test "returns default when key is not set" do
      Application.put_env(:my_app, :other_key, 1)

      assert Application.get_env(:my_app, :nonexistent_key, :default) == :default
    after
      Application.delete_env(:my_app, :other_key)
    end
  end
end
