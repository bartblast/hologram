defmodule Hologram.CompilerTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler

  @default_layout Application.get_env(:hologram, :default_layout)
  @module_2 Hologram.Test.Fixtures.Compiler.Module2
  @module_8 Hologram.Test.Fixtures.Compiler.Module8
  @module_11 Hologram.Test.Fixtures.Compiler.Module11

  test "includes the given module" do
    result = Compiler.compile(@module_2)
    assert Map.has_key?(result, @module_2)
  end

  test "includes aliased modules" do
    module_1 = Hologram.Test.Fixtures.Compiler.Module1
    result = Compiler.compile(module_1)

    assert Map.has_key?(result, @module_2)
  end

  test "includes imported modules" do
    module_5 = Hologram.Test.Fixtures.Compiler.Module5
    module_6 = Hologram.Test.Fixtures.Compiler.Module6
    result = Compiler.compile(module_5)

    assert Map.has_key?(result, module_6)
  end

  test "includes modules used by the given module's functions" do
    module_9 = Hologram.Test.Fixtures.Compiler.Module9
    result = Compiler.compile(@module_8)

    assert Map.has_key?(result, module_9)
  end

  test "handles circular dependency" do
    module_3 = Hologram.Test.Fixtures.Compiler.Module3
    module_4 = Hologram.Test.Fixtures.Compiler.Module4
    result = Compiler.compile(module_3)

    assert Map.has_key?(result, module_3)
    assert Map.has_key?(result, module_4)
  end

  test "doesn't include standard library modules" do
    module_7 = Hologram.Test.Fixtures.Compiler.Module7
    result = Compiler.compile(module_7)

    refute Map.has_key?(result, Map)
  end

  test "includes components used in template" do
    module_10 = Hologram.Test.Fixtures.Compiler.Module10
    result = Compiler.compile(module_10)

    assert Map.has_key?(result, @module_11)
  end

  test "include components used in slot" do
    module_12 = Hologram.Test.Fixtures.Compiler.Module12
    result = Compiler.compile(module_12)

    assert Map.has_key?(result, @module_11)
  end

  test "includes modules used in component props" do
    module_14 = Hologram.Test.Fixtures.Compiler.Module14
    result = Compiler.compile(module_14)

    assert Map.has_key?(result, @module_8)
  end

  test "includes modules used in element node attrs" do
    module_15 = Hologram.Test.Fixtures.Compiler.Module15
    result = Compiler.compile(module_15)

    assert Map.has_key?(result, @module_8)
  end

  test "includes modules used in text node expressions" do
    module_17 = Hologram.Test.Fixtures.Compiler.Module16
    result = Compiler.compile(module_17)

    assert Map.has_key?(result, @module_8)
  end

  test "includes modules used in nested nodes" do
    module_16 = Hologram.Test.Fixtures.Compiler.Module16
    result = Compiler.compile(module_16)

    assert Map.has_key?(result, @module_8)
  end

  test "includes layout modules for compiled page modules" do
    module_18 = Hologram.Test.Fixtures.Compiler.Module18
    result = Compiler.compile(module_18)

    assert Map.has_key?(result, @default_layout)
  end

  test "includes components used in the layout template" do
    module_18 = Hologram.Test.Fixtures.Compiler.Module18
    result = Compiler.compile(module_18)

    assert Map.has_key?(result, Hologram.UI.Runtime)
  end
end
