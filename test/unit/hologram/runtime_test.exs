defmodule Hologram.RuntimeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime
  alias Hologram.Test.Fixtures.Runtime.Module1

  test "reload_module/2" do
    source_path = Reflection.source_path(Module1)
    original_source_code = Reflection.source_code(Module1)

    assert Module1.test_fun() == 1

    updated_source_code = """
    defmodule Hologram.Test.Fixtures.Runtime.Module1 do
      def test_fun, do: 2
    end
    """

    File.write!(source_path, updated_source_code)
    Runtime.reload_module(Module1)

    assert Module1.test_fun() == 2

    File.write!(source_path, original_source_code)
  end
end
