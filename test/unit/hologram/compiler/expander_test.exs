defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Expander
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.IR.IgnoredExpression
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.MapType
  alias Hologram.Compiler.IR.ModuleAttributeDefinition
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.ModuleType
  alias Hologram.Test.Fixtures.Compiler.Expander.Module1

  test "addition operator" do
    ir = %IR.AdditionOperator{
      left: %IR.ModuleAttributeOperator{name: :a},
      right: %IR.ModuleAttributeOperator{name: :c}
    }

    context = %Context{
      module_attributes: %{
        a: %IR.IntegerType{value: 1},
        c: %IR.IntegerType{value: 3}
      }
    }

    result = Expander.expand(ir, context)

    assert result == %IR.AdditionOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 3}
           }
  end

  test "alias" do
    code = "A"
    ir = ir(code)
    result = Expander.expand(ir)

    assert {%ModuleType{module: A, segments: [:A]}, _context} = result
  end

  describe "alias directive" do
    test "single alias directive" do
      code = """
      alias A.B, as: C
      C
      """

      ir = ir(code)
      result = Expander.expand(ir)

      assert {
               %Block{
                 expressions: [
                   %IgnoredExpression{},
                   %ModuleType{module: A.B, segments: [:A, :B]}
                 ]
               },
               _context
             } = result
    end

    test "alias directive that uses an alias defined before it" do
      code = """
      alias A.B, as: C
      alias C.D, as: E
      E
      """

      ir = ir(code)
      result = Expander.expand(ir)

      assert {
               %Block{
                 expressions: [
                   %IgnoredExpression{},
                   %IgnoredExpression{},
                   %ModuleType{module: A.B.D, segments: [:A, :B, :D]}
                 ]
               },
               _context
             } = result
    end

    test "alias directive that uses an alias defined after it" do
      code = """
      alias C.D, as: E
      alias A.B, as: C
      E
      """

      ir = ir(code)
      result = Expander.expand(ir)

      assert {
               %Block{
                 expressions: [
                   %IgnoredExpression{},
                   %IgnoredExpression{},
                   %ModuleType{module: C.D, segments: [:C, :D]}
                 ]
               },
               _context
             } = result
    end
  end

  test "block" do
    code = """
    A
    B
    """

    ir = ir(code)
    result = Expander.expand(ir)

    assert {
             %Block{
               expressions: [
                 %ModuleType{module: A, segments: [:A]},
                 %ModuleType{module: B, segments: [:B]}
               ]
             },
             _context
           } = result
  end

  describe "import directive" do
    test "no opts" do
      code = "import Hologram.Test.Fixtures.Compiler.Expander.Module1"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               macro_3: %{2 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "'only' opt" do
      code =
        "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: [fun_2: 1, macro_3: 2]"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result
      assert context.functions == %{fun_2: %{1 => Module1}}
      assert context.macros == %{macro_3: %{2 => Module1}}
    end

    test "'except' opt" do
      code =
        "import Hologram.Test.Fixtures.Compiler.Expander.Module1, except: [fun_2: 1, macro_3: 2]"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only functions without 'except' opt" do
      code = "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :functions"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{}
    end

    test "only functions with 'except' opt" do
      code =
        "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :functions, except: [fun_1: 0, fun_3: 2]"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{
               fun_1: %{
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{}
    end

    test "only macros without 'except' opt" do
      code = "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :macros"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{}

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               macro_3: %{2 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only macros with 'except' opt" do
      code =
        "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :macros, except: [macro_1: 0, macro_3: 2]"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{}

      assert context.macros == %{
               macro_1: %{
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only sigils without 'except' opts" do
      code = "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :sigils"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only sigils with 'except' opts" do
      code =
        "import Hologram.Test.Fixtures.Compiler.Expander.Module1, only: :sigils, except: [sigil_b: 2, sigil_d: 2]"

      ir = ir(code)
      result = Expander.expand(ir)

      assert {%IgnoredExpression{}, %Context{} = context} = result
      assert context.functions == %{sigil_a: %{2 => Module1}}
      assert context.macros == %{sigil_c: %{2 => Module1}}
    end
  end

  describe "module attribute definition" do
    @context %Context{
      module_attributes: %{
        a: %IntegerType{value: 1},
        c: %IntegerType{value: 3}
      }
    }

    test "expression which doesn't use module attributes" do
      code = "@b 5 + 6"
      ir = ir(code)
      result = Expander.expand(ir, @context)

      assert {
               %IgnoredExpression{},
               %Context{
                 module_attributes: %{
                   a: %IntegerType{value: 1},
                   b: %IntegerType{value: 11},
                   c: %IntegerType{value: 3}
                 }
               }
             } = result
    end

    test "expression which uses module attributes" do
      code = "@b @a + @c"
      ir = ir(code)
      result = Expander.expand(ir, @context)

      assert {
               %IgnoredExpression{},
               %Context{
                 module_attributes: %{
                   a: %IntegerType{value: 1},
                   b: %IntegerType{value: 4},
                   c: %IntegerType{value: 3}
                 }
               }
             } = result
    end
  end

  test "module attribute operator" do
    ir = %ModuleAttributeOperator{name: :b}

    context = %Context{
      module_attributes: %{
        a: %IntegerType{value: 1},
        b: %IntegerType{value: 2}
      }
    }

    result = Expander.expand(ir, context)

    assert {%IntegerType{value: 2}, %Context{}} = result
  end
end
