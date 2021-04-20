defmodule Hologram.Transpiler.Transformers.ListTypeTransformerTest do
  use ExUnit.Case, async: true
  import Hologram.Transpiler.Parser, only: [parse!: 1]

  alias Hologram.Transpiler.AST.{IntegerType, ListType}
  alias Hologram.Transpiler.Transformers.ListTypeTransformer

  test "empty list" do
    result =
      parse!("[]")
      |> ListTypeTransformer.transform([:Abc], [], [])

    expected = %ListType{data: []}

    assert result == expected
  end

  test "non-nested list" do
    result =
      parse!("[1, 2]")
      |> ListTypeTransformer.transform([:Abc], [], [])

    expected = %ListType{
      data: [%IntegerType{value: 1}, %IntegerType{value: 2}]
    }

    assert result == expected
  end

  test "nested list" do
    result =
      parse!("[1, [2, [3, 4]]]")
      |> ListTypeTransformer.transform([:Abc], [], [])

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %ListType{
          data: [
            %IntegerType{value: 2},
            %ListType{
              data: [
                %IntegerType{value: 3},
                %IntegerType{value: 4}
              ]
            }
          ]
        }
      ]
    }

    assert result == expected
  end
end
