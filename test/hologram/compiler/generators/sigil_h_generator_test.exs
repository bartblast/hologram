defmodule Hologram.Compiler.SigilHGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, SigilHGenerator}
  alias Hologram.Compiler.IR.{BinaryType, FunctionCall, ListType, StringType}

  test "generate/2" do
    ir = %FunctionCall{
      function: :sigil_H,
      module: Hologram.Runtime.Commons,
      params: [
        %BinaryType{
          parts: [
            %StringType{value: "\n<div>Hello World {@counter}</div>\n"}
          ]
        },
        %ListType{data: []}
      ]
    }

    expected =
      "[ { type: 'element', tag: 'div', attrs: {}, children: [ { type: 'text', content: 'Hello World ' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ $state.data['~atom[counter]'] ] } } } ] } ]"

    result = SigilHGenerator.generate(ir, %Context{})
    assert result == expected
  end
end
