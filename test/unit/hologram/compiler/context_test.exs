defmodule Hologram.Compiler.ContextTest do
  use Hologram.Test.UnitCase, async: false
  alias Hologram.Compiler.Context

  # TODO: build env fields based on context data
  test "build_env/1" do
    result = Context.build_env(%Context{})
    assert result == %Macro.Env{}
  end

  describe "is_macro?/4" do
    @context %Context{
      functions: %{
        test_name: %{1 => Module1, 2 => Module2, 3 => Module3}
      },
      macros: %{
        test_name: %{4 => Module4, 5 => Module5, 6 => Module6}
      }
    }

    test "yes" do
      assert Context.is_macro?(@context, Module5, :test_name, 5)
    end

    test "no" do
      refute Context.is_macro?(@context, Module2, :test_name, 2)
      refute Context.is_macro?(@context, Module5, :test_name, 4)
    end
  end

  test "put_functions/3" do
    context = %Context{
      functions: %{fun_1: %{1 => Module1, 2 => Module2}, fun_2: %{3 => Module3, 4 => Module4}}
    }

    added_functions = [fun_1: 1, fun_1: 3, fun_3: 5]
    result = Context.put_functions(context, Module5, added_functions)

    expected = %Context{
      functions: %{
        fun_1: %{1 => Module5, 2 => Module2, 3 => Module5},
        fun_2: %{3 => Module3, 4 => Module4},
        fun_3: %{5 => Module5}
      }
    }

    assert result == expected
  end

  test "put_macros/3" do
    context = %Context{
      macros: %{macro_1: %{1 => Module1, 2 => Module2}, macro_2: %{3 => Module3, 4 => Module4}}
    }

    added_macros = [macro_1: 1, macro_1: 3, macro_3: 5]
    result = Context.put_macros(context, Module5, added_macros)

    expected = %Context{
      macros: %{
        macro_1: %{1 => Module5, 2 => Module2, 3 => Module5},
        macro_2: %{3 => Module3, 4 => Module4},
        macro_3: %{5 => Module5}
      }
    }

    assert result == expected
  end

  test "put_module_attribute/3" do
    context = %Context{module_attributes: %{a: :value_a, c: :value_c}}
    result = Context.put_module_attribute(context, :b, :value_b)

    assert result == %Context{
             module_attributes: %{a: :value_a, b: :value_b, c: :value_c}
           }
  end

  describe "resolve_function_module/3" do
    test "function exists" do
      context = %Context{
        functions: %{
          fun_1: %{1 => Module1, 2 => Module2, 3 => Module3}
        }
      }

      result = Context.resolve_function_module(context, :fun_1, 2)
      assert result == Module2
    end

    test "function doesn't exist" do
      context = %Context{
        functions: %{
          fun_2: %{1 => Module1, 2 => Module2, 3 => Module3}
        }
      }

      result = Context.resolve_function_module(context, :fun_1, 2)
      refute result
    end
  end

  describe "resolve_macro_module/3" do
    test "macro exists" do
      context = %Context{
        macros: %{
          macro_1: %{1 => Module1, 2 => Module2, 3 => Module3}
        }
      }

      result = Context.resolve_macro_module(context, :macro_1, 2)
      assert result == Module2
    end

    test "macro doesn't exist" do
      context = %Context{
        macros: %{
          macro_2: %{1 => Module1, 2 => Module2, 3 => Module3}
        }
      }

      result = Context.resolve_macro_module(context, :macro_1, 2)
      refute result
    end
  end
end
