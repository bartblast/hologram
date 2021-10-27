defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.{MacroDefinition, ModuleDefinition, UseDirective}
  alias Hologram.Compiler.Reflection

  @module_1 Hologram.Test.Fixtures.Compiler.Reflection.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Reflection.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.Reflection.Module4
  @module_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Reflection, :Module1]

  setup_all do
    on_exit(&compile_pages/0)
  end

  describe "app_path/1" do
    test "default" do
      result = Reflection.app_path([])
      expected = "#{File.cwd!()}/app"

      assert result == expected
    end

    test "custom" do
      expected = "/test/path"
      config = [app_path: expected]
      result = Reflection.app_path(config)

      assert result == expected
    end
  end

  test "get_page_digest/1" do
    compile_pages()
    result = Reflection.get_page_digest(Elixir.Hologram.E2E.Page1)
    assert result =~ uuid_hex_regex()
  end

  describe "has_function?/3" do
    test "returns true if the module has a function with the arity" do
      assert Reflection.has_function?(@module_4, :test_fun, 2)
    end

    test "returns false if the module doesn't have a function with the arity" do
      refute Reflection.has_function?(@module_4, :test_fun, 3)
    end
  end

  describe "has_template?/1" do
    test "true" do
      module = Hologram.Test.Fixtures.Compiler.Reflection.Module3
      assert Reflection.has_template?(module)
    end

    test "false" do
      module = Hologram.Compiler.ReflectionTest
      refute Reflection.has_template?(module)
    end
  end

  test "macro_definition/3" do
    result = Reflection.macro_definition(@module_2, :test_macro, [1, 2])
    assert %MacroDefinition{arity: 2, name: :test_macro} = result
  end

  describe "module?/1" do
    test "is module" do
      assert Reflection.module?(Hologram.Compiler.ReflectionTest)
    end

    test "is atom" do
      refute Reflection.module?(:test)
    end

    test "is Erlang module" do
      refute Reflection.module?(:c)
    end
  end

  describe "module_ast/1" do
    @expected {:defmodule, [line: 1],
               [
                 {:__aliases__, [line: 1], @module_segs_1},
                 [do: {:__block__, [], []}]
               ]}

    test "module segments arg" do
      result = Reflection.ast(@module_segs_1)
      assert result == @expected
    end

    test "module arg" do
      result = Reflection.ast(@module_1)
      assert result == @expected
    end
  end

  test "module_definition/1" do
    result = Reflection.module_definition(@module_1)
    assert %ModuleDefinition{module: @module_1} = result
  end

  test "otp_app/0" do
    assert Reflection.otp_app() == :hologram
  end

  describe "pages_path/1" do
    test "default" do
      result = Reflection.pages_path([])
      expected = "#{File.cwd!()}/e2e/pages"

      assert result == expected
    end

    test "custom" do
      expected = "/test/path"
      opts = [pages_path: expected]
      result = Reflection.pages_path(opts)

      assert result == expected
    end
  end

  describe "root_path/0" do
    test "default" do
      result = Reflection.root_path([])
      expected = File.cwd!()

      assert result == expected
    end

    test "custom" do
      expected = "/test/path"
      config = [root_path: expected]
      result = Reflection.root_path(config)

      assert result == expected
    end
  end

  describe "router_module/1" do
    test "default" do
      result = Reflection.router_module([])
      expected = HologramWeb.Router

      assert result == expected
    end

    test "custom" do
      expected = Abc.Bcd
      config = [router_module: expected]
      result = Reflection.router_module(config)

      assert result == expected
    end
  end

  test "router_path/0" do
    result = Reflection.router_path()
    expected = "#{File.cwd!()}/e2e/phoenix/web/router.ex"

    assert result == expected
  end

  test "source_path/1" do
    result = Reflection.source_path(Hologram.Compiler.ReflectionTest)
    expected = __ENV__.file

    assert result == expected
  end

  describe "standard_lib?/1" do
    test "standard lib module" do
      assert Reflection.standard_lib?(Map)
    end

    test "app module" do
      refute Reflection.standard_lib?(Hologram.E2E.Page1)
    end

    test "lib module" do
      refute Reflection.standard_lib?(Hologram.Compiler)
    end

    test "test module" do
      refute Reflection.standard_lib?(Hologram.Compiler.ReflectionTest)
    end

    test "deps module" do
      refute Reflection.standard_lib?(Phoenix)
    end
  end

  describe "templatable/1" do
    test "component" do
      module_def = %ModuleDefinition{uses: [%UseDirective{module: Hologram.Component}]}
      assert Reflection.templatable?(module_def)
    end

    test "page" do
      module_def = %ModuleDefinition{uses: [%UseDirective{module: Hologram.Page}]}
      assert Reflection.templatable?(module_def)
    end

    test "layout" do
      module_def = %ModuleDefinition{uses: [%UseDirective{module: Hologram.Layout}]}
      assert Reflection.templatable?(module_def)
    end

    test "other modules" do
      module_def = %ModuleDefinition{uses: []}
      refute Reflection.templatable?(module_def)
    end
  end
end
