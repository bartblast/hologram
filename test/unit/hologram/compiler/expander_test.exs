defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Expander
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.IR.IgnoredExpression
  alias Hologram.Compiler.IR.ModuleType

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
end
