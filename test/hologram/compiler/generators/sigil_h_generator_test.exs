defmodule Hologram.Compiler.SigilHGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, SigilHGenerator}
  alias Hologram.Compiler.IR.{BinaryType, FunctionCall, ListType, StringType}

  test "generate/2" do
    ir =
      %FunctionCall{
        function: :sigil_H,
        module: Hologram.Runtime.Commons,
        params: [
          %BinaryType{
            parts: [
              %StringType{value: "<div>Hello World {@counter}</div>\n"}
            ]
          },
          %ListType{data: []}
        ]
      }

    expected = "[{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'Hello World ' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ $state.data['~atom[counter]'] ] } } }] }, { type: 'text', content: '\\n' }]"

    result = SigilHGenerator.generate(ir, %Context{})
    assert result == expected
  end
end
