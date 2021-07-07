defmodule Hologram.Compiler.SigilHGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, ListType, StringType}
  alias Hologram.Compiler.SigilHGenerator

  test "generate/2" do
    ir =
      %FunctionCall{
        function: :sigil_H,
        module: [:Hologram, :Runtime, :Commons],
        params: [
          %FunctionCall{
            function: :<<>>,
            module: [:Kernel],
            params: [
              %StringType{
                value: "<div>Hello World {{ @counter }}</div>\n"
              }
            ]
          },
          %ListType{data: []}
        ]
      }

    context = [aliases: []]
    
    expected = "[{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'Hello World ' }, { type: 'expression', callback: ($state) => { return $state.data['~atom[counter]'] } }] }, { type: 'text', content: '\\n' }]"

    result = SigilHGenerator.generate(ir, context)
    assert result == expected
  end
end
