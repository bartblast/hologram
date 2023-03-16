defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{Context, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, MacroDefinition, ModuleDefinition}
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module7
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module8

  @config_app_path Application.get_env(:hologram, :app_path)

  @alias_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Reflection, :Module1]
  @module_1 Hologram.Test.Fixtures.Compiler.Reflection.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Reflection.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.Reflection.Module4
  @module_6 Hologram.Test.Fixtures.Compiler.Reflection.Module6

  describe "app_path/1" do
    test "default" do
      Application.delete_env(:hologram, :app_path)

      result = Reflection.app_path()
      expected = "#{File.cwd!()}/lib"

      assert result == expected

      if @config_app_path do
        Application.put_env(:hologram, :app_path, @config_app_path)
      end
    end

    test "config" do
      expected = "/test-config-path"
      Application.put_env(:hologram, :app_path, expected)

      assert Reflection.app_path() == expected

      if @config_app_path do
        Application.put_env(:hologram, :app_path, @config_app_path)
      else
        Application.delete_env(:hologram, :app_path)
      end
    end

    test "opts" do
      expected = "/test-opts-path"
      opts = [app_path: expected]

      assert Reflection.app_path(opts) == expected
    end
  end

  describe "ast/1" do
    @expected {:defmodule, [line: 1],
               [
                 {:__aliases__, [line: 1], @alias_segs_1},
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
      result = Reflection.ast(@alias_segs_1)
      assert result == @expected
    end
  end

  test "functions/1" do
    result = Reflection.functions(Kernel)

    assert {:apply, 2} in result
    refute {:def, 2} in result
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

    test "returns false if the first arg is not a module" do
      refute Reflection.has_macro?(NotLoadedModuleFixture, :test_macro, 3)
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

  test "hologram_ui_components_path/0" do
    result = Reflection.hologram_ui_components_path()
    expected = "#{File.cwd!()}/lib/hologram/ui"

    assert result == expected
  end

  test "ir/1" do
    code = "def fun, do: 1"
    result = Reflection.ir(code)

    assert %FunctionDefinition{name: :fun} = result
  end

  describe "is_ignored_module?/1" do
    test "module belonging to hardcoded list of ignored modules" do
      assert Reflection.is_ignored_module?(Ecto.Changeset)
    end

    # DEFER: implement
    # test "module specified to be ignored in config"

    test "module belonging to ignored namespace" do
      assert Reflection.is_ignored_module?(Hologram.Compiler.Reflection)
    end

    test "not ignored module" do
      refute Reflection.is_ignored_module?(Hologram.Runtime.Page)
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

    test "atom which is not a module or protocol alias" do
      refute Reflection.is_protocol?(Abc.Bcd)
    end

    test "atom which is not an alias" do
      refute Reflection.is_protocol?(:abc)
    end

    test "non-atom" do
      refute Reflection.is_protocol?(123)
    end
  end

  test "list_components/1" do
    num_app_components =
      "#{Reflection.app_path()}/components/*"
      |> Path.wildcard()
      |> Enum.count()

    num_hologram_ui_components =
      "#{Reflection.hologram_ui_components_path()}/*"
      |> Path.wildcard()
      |> Enum.count()

    result = Reflection.list_components()

    assert Enum.count(result) == num_app_components + num_hologram_ui_components
    assert Hologram.Test.Fixtures.App.Component1 in result
    assert Hologram.UI.Runtime in result
  end

  test "list_layouts/1" do
    num_layouts =
      "#{Reflection.app_path()}/layouts/*"
      |> Path.wildcard()
      |> Enum.count()

    result = Reflection.list_layouts()

    assert Enum.count(result) == num_layouts
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
      "#{Reflection.app_path()}/pages/*"
      |> Path.wildcard()
      |> Enum.count()

    result = Reflection.list_pages()

    assert Enum.count(result) == num_pages
  end

  test "list_templates/1" do
    templatables = [Module7, Module8]
    result = Reflection.list_templates(templatables)

    expected = [
      {Module7,
       [
         %ElementNode{
           attrs: %{},
           children: [%TextNode{content: "template 7"}],
           tag: "div"
         }
       ]},
      {Module8,
       [
         %ElementNode{
           attrs: %{},
           children: [%TextNode{content: "template 8"}],
           tag: "div"
         }
       ]}
    ]

    assert result == expected
  end

  test "macro_definition/3" do
    result = Reflection.macro_definition(@module_2, :test_macro, [1, 2])
    assert %MacroDefinition{arity: 2, name: :test_macro} = result
  end

  test "macros/1" do
    result = Reflection.macros(Kernel)

    assert {:def, 2} in result
    refute {:apply, 2} in result
  end

  test "module_definition/1" do
    result = Reflection.module_definition(@module_1)
    assert %ModuleDefinition{module: @module_1} = result
  end

  test "otp_app/0" do
    assert Reflection.otp_app() == :hologram
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
      refute Reflection.standard_lib?(Hologram.Test.Fixtures.Compiler.Reflection.Module1)
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
