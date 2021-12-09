defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{Context, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, MacroDefinition, ModuleDefinition}

  @module_1 Hologram.Test.Fixtures.Compiler.Reflection.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Reflection.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.Reflection.Module4
  @module_6 Hologram.Test.Fixtures.Compiler.Reflection.Module6
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

  describe "ast/1" do
    @expected {:defmodule, [line: 1],
               [
                 {:__aliases__, [line: 1], @module_segs_1},
                 [do: {:__block__, [], []}]
               ]}

    test "atom arg (module)" do
      result = Reflection.ast(@module_1)
      assert result == @expected
    end

    test "binary arg (code)" do
      code = "defmodule Hologram.Test.Fixtures.Compiler.Reflection.Module1 do\nend\n"
      result = Reflection.ast(code)

      assert result == @expected
    end

    test "list arg (module segments)" do
      result = Reflection.ast(@module_segs_1)
      assert result == @expected
    end
  end

  test "get_page_digest/1" do
    compile_pages()
    result = Reflection.get_page_digest(Elixir.Hologram.E2E.Page1)
    assert result =~ uuid_hex_regex()
  end

  describe "has_function?/3" do
    test "returns true if the module has a function with the given name and arity" do
      assert Reflection.has_function?(@module_4, :test_fun, 2)
    end

    test "returns false if the module doesn't have a function with the given name and arity" do
      refute Reflection.has_function?(@module_4, :test_fun, 3)
    end
  end

  describe "has_macro?/3" do
    test "returns true if the module has a macro with the given name and arity" do
      assert Reflection.has_macro?(@module_6, :test_macro, 2)
    end

    test "returns false if the module doesn't have a macro with the given name and arity" do
      refute Reflection.has_macro?(@module_6, :test_macro, 3)
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

  test "ir/1" do
    code = "def fun, do: 1"
    context = %Context{module: Abc.Bcd}
    result = Reflection.ir(code, context)

    assert %FunctionDefinition{module: Abc.Bcd} = result
  end

  describe "is_alias?/1" do
    test "atom which is a module alias" do
      assert Reflection.is_alias?(Kernel)
    end

    test "atom which is a protocol alias" do
      assert Reflection.is_alias?(Enumerable)
    end

    test "atom which is not an alias" do
      refute Reflection.is_alias?(:abc)
    end

    test "non-atom" do
      refute Reflection.is_alias?(123)
    end
  end

  describe "is_module?/1" do
    test "atom which is a module alias" do
      assert Reflection.is_module?(Kernel)
    end

    test "atom which is a protocol alias" do
      refute Reflection.is_module?(Enumerable)
    end

    test "atom which is not an alias" do
      refute Reflection.is_module?(:abc)
    end

    test "non-atom" do
      refute Reflection.is_module?(123)
    end
  end

  describe "is_protocol?/1" do
    test "atom which is a module alias" do
      refute Reflection.is_protocol?(Kernel)
    end

    test "atom which is a protocol alias" do
      assert Reflection.is_protocol?(Enumerable)
    end

    test "atom which is not an alias" do
      refute Reflection.is_protocol?(:abc)
    end

    test "non-atom" do
      refute Reflection.is_protocol?(123)
    end
  end

  describe "list_modules/1" do
    test "includes app modules" do
      result = Reflection.list_modules(:hologram)
      assert Hologram.Compiler.Reflection in result
    end

    test "doesn't include standard lib modules" do
      result = Reflection.list_modules(:hologram)
      refute Kernel in result
    end
  end

  test "list_pages/1" do
    num_pages =
      "#{Reflection.pages_path()}/*"
      |> Path.wildcard()
      |> Enum.count()

    result = Reflection.list_pages()

    assert Enum.count(result) == num_pages
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

  test "module_definition/1" do
    result = Reflection.module_definition(@module_1)
    assert %ModuleDefinition{module: @module_1} = result
  end

  test "otp_app/0" do
    assert Reflection.otp_app() == :hologram
  end

  describe "pages_path/1" do
    test "default" do
      result = Reflection.pages_path()
      expected = "#{File.cwd!()}/e2e/pages"

      assert result == expected
    end

    test "opts" do
      config_pages_path = "/test/config/pages/path"
      Application.put_env(:hologram, :pages_path, config_pages_path)

      opts_pages_path = "/test/opts/pages/path"
      opts = [pages_path: opts_pages_path]

      result = Reflection.pages_path(opts)
      assert result == opts_pages_path

      Application.delete_env(:hologram, :pages_path)
    end

    test "config" do
      config_pages_path = "/test/config/pages/path"
      Application.put_env(:hologram, :pages_path, config_pages_path)

      result = Reflection.pages_path()
      assert result == config_pages_path

      Application.delete_env(:hologram, :pages_path)
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

  test "source_code/1" do
    module = Hologram.Test.Fixtures.Compiler.Reflection.Module5

    result = Reflection.source_code(module)
    expected = "defmodule Hologram.Test.Fixtures.Compiler.Reflection.Module5 do\nend\n"

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
      refute Reflection.standard_lib?(Hologram.Compiler.Transformer)
    end

    test "test module" do
      refute Reflection.standard_lib?(Hologram.Compiler.ReflectionTest)
    end

    test "deps module" do
      refute Reflection.standard_lib?(Phoenix)
    end
  end
end
