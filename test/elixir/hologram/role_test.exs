defmodule Hologram.RoleTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Role.Module1
  alias Hologram.Test.Fixtures.Role.Module2

  describe "__extends__/0" do
    test "returns empty list when the role extends nothing" do
      assert Module1.__extends__() == []
    end

    test "wraps a single role module" do
      assert Module2.__extends__() == [Module1]
    end

    test "keeps a list of role modules in declaration order" do
      defmodule MultiExtendsFixture do
        use Hologram.Role, extends: [Module2, Module1]
      end

      assert MultiExtendsFixture.__extends__() == [Module2, Module1]
    end
  end

  describe "__is_hologram_role__/0" do
    test "returns true" do
      assert Module1.__is_hologram_role__()
    end
  end

  describe "use Hologram.Role" do
    test "raises for an unknown option" do
      expected_msg =
        "unknown option :scope for use Hologram.Role in Hologram.RoleTest.UnknownOptFixture - valid options are: :extends"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule UnknownOptFixture do
          use Hologram.Role, scope: :global
        end
      end
    end

    test "raises for options that are not a keyword list" do
      expected_msg =
        "invalid options :extends for use Hologram.Role in Hologram.RoleTest.InvalidOptsFixture - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InvalidOptsFixture do
          use Hologram.Role, :extends
        end
      end
    end
  end
end
