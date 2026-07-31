defmodule Hologram.ExJsConsistency.Erlang.ApplicationTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/application_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "get_application/1" do
    test "module belonging to an application" do
      assert :application.get_application(Hologram) == {:ok, :hologram}
    end

    # Case not possible on the server - every loaded module belongs to an
    # application, whereas the client places a module only when the compiler
    # emitted its metadata.
    # test "module carrying no metadata"

    test "module that isn't in the bundle" do
      assert :application.get_application(NoSuchModule) == :undefined
    end

    test "raises FunctionClauseError if the argument is not an atom" do
      module = wrap_term(123)

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":application.get_application/1", [123]),
                   fn -> :application.get_application(module) end
    end
  end

  describe "get_key/2" do
    test "vsn of a known application" do
      assert {:ok, vsn} = :application.get_key(:hologram, :vsn)
      assert is_list(vsn)
    end

    test "vsn of an unknown application" do
      assert :application.get_key(:no_such_app, :vsn) == :undefined
    end

    # The client carries each application's version and nothing else of its
    # specification, so it answers :undefined here, whereas the server answers
    # with the value the application defines.
    test "key other than vsn" do
      assert {:ok, description} = :application.get_key(:hologram, :description)
      assert is_list(description)
    end

    test "application that is not an atom" do
      app = wrap_term("hologram")

      assert :application.get_key(app, :vsn) == :undefined
    end

    test "key that is not an atom" do
      assert :application.get_key(:hologram, wrap_term("vsn")) == :undefined
    end
  end
end
