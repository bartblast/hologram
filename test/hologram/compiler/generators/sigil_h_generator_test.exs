defmodule Hologram.Compiler.SigilHGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, SigilHGenerator}
  alias Hologram.Compiler.IR.{FunctionCall, ListType, StringType}

  test "generate/2" do
    ir =
      %FunctionCall{
        function: :sigil_H,
        module: Hologram.Runtime.Commons,
        params: [
          %FunctionCall{
            function: :<<>>,
            module: Kernel,
            params: [
              %StringType{
                value: "<div>Hello World {{ @counter }}</div>\n"
              }
            ]
          },
          %ListType{data: []}
        ]
      }

    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    expected = "[{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'Hello World ' }, { type: 'expression', callback: ($state) => { return $state.data['~atom[counter]'] } }] }, { type: 'text', content: '\\n' }]"

    result = SigilHGenerator.generate(ir, context)
    assert result == expected
  end
end
