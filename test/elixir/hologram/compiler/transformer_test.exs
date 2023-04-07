defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  describe "anonymous function call" do
    test "without args" do
      # test.()
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: []
             }
    end

    test "with args" do
      # test.(1, 2)
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], [1, 2]}

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "atom type" do
    test "boolean" do
      # true
      ast = true

      assert transform(ast, %Context{}) == %IR.AtomType{value: true}
    end

    test "nil" do
      # nil
      ast = nil

      assert transform(ast, %Context{}) == %IR.AtomType{value: nil}
    end

    test "other than boolean or nil" do
      # :test
      ast = :test

      assert transform(ast, %Context{}) == %IR.AtomType{value: :test}
    end
  end

  describe "bitstring type" do
    test "empty" do
      # <<>>
      ast = {:<<>>, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.BitstringType{segments: []}
    end

    test "single segment" do
      # <<987>>
      ast = {:<<>>, [line: 1], [987]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{}]} = transform(ast, %Context{})
    end

    test "multiple segments" do
      # <<987, 876>>
      ast = {:<<>>, [line: 1], [987, 876]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{}, %IR.BitstringSegment{}]} =
               transform(ast, %Context{})
    end

    # --- ENDIANNESS MODIFIER ---

    test "default endianness" do
      # <<xyz>>
      ast = {:<<>>, [line: 1], [{:xyz, [line: 1], nil}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{endianness: :big}]} =
               transform(ast, %Context{})
    end

    test "big endianness modifier" do
      # <<xyz::big>>
      ast =
        {:<<>>, [line: 1], [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:big, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{endianness: :big}]} =
               transform(ast, %Context{})
    end

    test "little endianness modifier" do
      # <<xyz::little>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:little, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{endianness: :little}]} =
               transform(ast, %Context{})
    end

    test "native endianness modifier" do
      # <<xyz::native>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:native, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{endianness: :native}]} =
               transform(ast, %Context{})
    end

    # --- SIGNEDNESS MODIFIER ---

    test "default signedness" do
      # <<xyz>>
      ast = {:<<>>, [line: 1], [{:xyz, [line: 1], nil}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{signedness: :unsigned}]} =
               transform(ast, %Context{})
    end

    test "signed signedness modifier" do
      # <<xyz::signed>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:signed, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{signedness: :signed}]} =
               transform(ast, %Context{})
    end

    test "unsigned signedness modifier" do
      # <<xyz::unsigned>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:unsigned, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{signedness: :unsigned}]} =
               transform(ast, %Context{})
    end

    # --- SIZE MODIFIER ---

    test "default size for float type" do
      # <<xyz::float>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:float, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: 64}]} =
               transform(ast, %Context{})
    end

    test "default size for integer type" do
      # <<xyz::integer>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:integer, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: 8}]} =
               transform(ast, %Context{})
    end

    test "default size for types other than float or integer" do
      # <<xyz::binary>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:binary, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: nil}]} =
               transform(ast, %Context{})
    end

    test "explicit size modifier syntax" do
      # <<xyz::size(3)>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:size, [line: 1], [3]}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: 3}]} =
               transform(ast, %Context{})
    end

    test "shorthand size modifier syntax" do
      # <<xyz::3>>
      ast = {:<<>>, [line: 1], [{:"::", [line: 1], [{:xyz, [line: 1], nil}, 3]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: 3}]} =
               transform(ast, %Context{})
    end

    test "shorthand size modifier syntax inside size * unit group" do
      # <<xyz::3*5>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:*, [line: 1], [3, 5]}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{size: 3}]} =
               transform(ast, %Context{})
    end

    # --- TYPE MODIFIER ---

    test "default type" do
      # <<xyz>>
      ast = {:<<>>, [line: 1], [{:xyz, [line: 1], nil}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :integer}]} =
               transform(ast, %Context{})
    end

    test "binary type modifier" do
      # <<xyz::binary>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:binary, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :binary}]} =
               transform(ast, %Context{})
    end

    test "bits type modifier" do
      # <<xyz::bits>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:bits, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :bitstring}]} =
               transform(ast, %Context{})
    end

    test "bitstring type modifier" do
      # <<xyz::bitstring>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:bitstring, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :bitstring}]} =
               transform(ast, %Context{})
    end

    test "bytes type modifier" do
      # <<xyz::bytes>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:bytes, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :binary}]} =
               transform(ast, %Context{})
    end

    test "float type modifier" do
      # <<xyz::float>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:float, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :float}]} =
               transform(ast, %Context{})
    end

    test "integer type modifier" do
      # <<xyz::integer>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:integer, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :integer}]} =
               transform(ast, %Context{})
    end

    test "utf8 type modifier" do
      # <<xyz::utf8>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:utf8, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :utf8}]} =
               transform(ast, %Context{})
    end

    test "utf16 type modifier" do
      # <<xyz::utf16>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:utf16, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :utf16}]} =
               transform(ast, %Context{})
    end

    test "utf32 type modifier" do
      # <<xyz::utf32>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:utf32, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{type: :utf32}]} =
               transform(ast, %Context{})
    end

    # --- UNIT MODIFIER ---

    test "default unit for binary type" do
      # <<xyz::binary>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:binary, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: 8}]} =
               transform(ast, %Context{})
    end

    test "default unit for float type" do
      # <<xyz::float>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:float, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: 1}]} =
               transform(ast, %Context{})
    end

    test "default unit for integer type" do
      # <<xyz::integer>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:integer, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: 1}]} =
               transform(ast, %Context{})
    end

    test "default unit for types other than binary, float or integer" do
      # <<xyz::utf32>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:utf32, [line: 1], nil}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: nil}]} =
               transform(ast, %Context{})
    end

    test "explicit unit modifier syntax" do
      # <<xyz::unit(3)>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:unit, [line: 1], [3]}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: 3}]} =
               transform(ast, %Context{})
    end

    test "shorthand unit modifier syntax inside size * unit group" do
      # <<xyz::3*5>>
      ast =
        {:<<>>, [line: 1],
         [{:"::", [line: 1], [{:xyz, [line: 1], nil}, {:*, [line: 1], [3, 5]}]}]}

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{unit: 5}]} =
               transform(ast, %Context{})
    end
  end

  test "cons operatoror" do
    # [h | t]
    ast = [{:|, [line: 1], [{:h, [line: 1], nil}, {:t, [line: 1], nil}]}]

    assert transform(ast, %Context{}) == %IR.ConsOperator{
             head: %IR.Variable{name: :h},
             tail: %IR.Variable{name: :t}
           }
  end

  test "dot operator" do
    # abc.x
    ast = {{:., [line: 1], [{:abc, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}

    assert transform(ast, %Context{}) == %IR.DotOperator{
             left: %IR.Variable{name: :abc},
             right: %IR.AtomType{value: :x}
           }
  end

  test "float type" do
    # 1.0
    ast = 1.0

    assert transform(ast, %Context{}) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    # 1
    ast = 1

    assert transform(ast, %Context{}) == %IR.IntegerType{value: 1}
  end

  test "list type" do
    # [1, 2]
    ast = [1, 2]

    assert transform(ast, %Context{}) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  describe "local function call" do
    test "without args" do
      # my_fun()
      ast = {:my_fun, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{function: :my_fun, args: []}
    end

    test "with args" do
      # my_fun(1, 2)
      ast = {:my_fun, [line: 1], [1, 2]}

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "map type " do
    test "without cons operator" do
      # %{a: 1, b: 2}
      ast = {:%{}, [line: 1], [a: 1, b: 2]}

      assert transform(ast, %Context{}) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "with cons operator" do
      # %{x | a: 1, b: 2}
      ast = {:%{}, [line: 1], [{:|, [line: 1], [{:x, [line: 1], nil}, [a: 1, b: 2]]}]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x},
                 %IR.MapType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :a},
                         %IR.IntegerType{value: 1}
                       ]
                     },
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :b},
                         %IR.IntegerType{value: 2}
                       ]
                     }
                   ]
                 }
               ]
             }
    end
  end

  test "match operator" do
    # %{a: x, b: y} = %{a: 1, b: 2}
    ast =
      {:=, [line: 1],
       [
         {:%{}, [line: 1], [a: {:x, [line: 1], nil}, b: {:y, [line: 1], nil}]},
         {:%{}, [line: 1], [a: 1, b: 2]}
       ]}

    assert transform(ast, %Context{}) == %IR.MatchOperator{
             left: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.Variable{name: :x}},
                 {%IR.AtomType{value: :b}, %IR.Variable{name: :y}}
               ]
             },
             right: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
           }
  end

  test "match placeholder" do
    # _abc
    ast = {:_abc, [line: 1], nil}

    assert transform(ast, %Context{}) == %IR.MatchPlaceholder{}
  end

  test "module attribute operator" do
    # @my_attr
    ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

    assert transform(ast, %Context{}) == %IR.ModuleAttributeOperator{name: :my_attr}
  end

  describe "module" do
    test "when first alias segment is not 'Elixir'" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end

    test "when first alias segment is 'Elixir'" do
      # Elixir.Aaa.Bbb
      ast = {:__aliases__, [line: 1], [Elixir, :Aaa, :Bbb]}

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end
  end

  test "pin operator" do
    # ^my_var
    ast = {:^, [line: 1], [{:my_var, [line: 1], nil}]}

    assert transform(ast, %Context{}) == %IR.PinOperator{name: :my_var}
  end

  describe "remote function call" do
    # Remote call on variable, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on variable, without args, with parenthesis" do
      # a.x()
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :a},
               function: :x,
               args: []
             }
    end

    test "on variable, with args" do
      # a.x(1, 2)
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], [1, 2]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :a},
               function: :x,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on alias, without args, without parenthesis" do
      # Abc.my_fun
      ast =
        {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]},
         [no_parens: true, line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, without args, with parenthesis" do
      # Abc.my_fun()
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, with args" do
      # Abc.my_fun(1, 2)
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # Remote call on module attribute, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on module attribute, without args" do
      # @my_attr.my_fun()
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: []
             }
    end

    test "on module attribute, with args" do
      # @my_attr.my_fun(1, 2)
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1],
         [1, 2]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # Remote call on expression, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on expression, without args" do
      # (anon_fun.(1, 2)).remote_fun()
      ast =
        {{:., [line: 1],
          [
            {{:., [line: 1], [{:anon_fun, [line: 1], nil}]}, [line: 1], [1, 2]},
            :remote_fun
          ]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun},
                 args: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               },
               function: :remote_fun,
               args: []
             }
    end

    test "on expression, with args" do
      # (anon_fun.(1, 2)).remote_fun(3, 4)
      ast =
        {{:., [line: 1],
          [
            {{:., [line: 1], [{:anon_fun, [line: 1], nil}]}, [line: 1], [1, 2]},
            :remote_fun
          ]}, [line: 1], [3, 4]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun},
                 args: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               },
               function: :remote_fun,
               args: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 4}
               ]
             }
    end

    test "on Erlang module, without args, without parenthesis" do
      # :my_module.my_fun
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [no_parens: true, line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: []
             }
    end

    test "on Erlang module, without args, with parenthesis" do
      # :my_module.my_fun()
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [line: 1], []}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: []
             }
    end

    test "on Erlang module, with args" do
      # :my_module.my_fun(1, 2)
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  test "string type" do
    # "abc"
    ast = "abc"

    assert transform(ast, %Context{}) == %IR.StringType{value: "abc"}
  end

  describe "struct" do
    # %Aaa.Bbb{a: 1, b: 2}
    @ast {:%, [line: 1],
          [{:__aliases__, [line: 1], [:Aaa, :Bbb]}, {:%{}, [line: 1], [a: 1, b: 2]}]}

    test "without cons operator, not in pattern" do
      context = %Context{pattern?: false}

      assert transform(@ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Aaa.Bbb},
               function: :__struct__,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :a},
                         %IR.IntegerType{value: 1}
                       ]
                     },
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :b},
                         %IR.IntegerType{value: 2}
                       ]
                     }
                   ]
                 }
               ]
             }
    end

    test "without cons operator, in pattern, with module specified" do
      context = %Context{pattern?: true}

      assert transform(@ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Aaa.Bbb}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "without cons operator, in pattern, with match placeholder instead of module" do
      # %_{a: 1, b: 2}
      ast = {:%, [line: 1], [{:_, [line: 1], nil}, {:%{}, [line: 1], [a: 1, b: 2]}]}

      context = %Context{pattern?: true}

      assert transform(ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.MatchPlaceholder{}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    # Case not possible, since it wouldn't compile:
    # test "without cons operator, not in pattern, with match placeholder instead of module"

    test "with cons operator, not in pattern" do
      # %Aaa.Bbb{x | a: 1, b: 2}
      ast =
        {:%, [line: 1],
         [
           {:__aliases__, [line: 1], [:Aaa, :Bbb]},
           {:%{}, [line: 1], [{:|, [line: 1], [{:x, [line: 1], nil}, [a: 1, b: 2]]}]}
         ]}

      context = %Context{pattern?: false}

      assert transform(ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x},
                 %IR.RemoteFunctionCall{
                   module: %IR.AtomType{value: Aaa.Bbb},
                   function: :__struct__,
                   args: [
                     %IR.ListType{
                       data: [
                         %IR.TupleType{
                           data: [
                             %IR.AtomType{value: :a},
                             %IR.IntegerType{value: 1}
                           ]
                         },
                         %IR.TupleType{
                           data: [
                             %IR.AtomType{value: :b},
                             %IR.IntegerType{value: 2}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               ]
             }
    end

    # Case not possible, since it wouldn't compile:
    # test "with cons operator, in pattern"
  end

  describe "tuple type" do
    test "2-element tuple" do
      # {1, 2}
      ast = {1, 2}

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "non-2-element tuple" do
      # {1, 2, 3}
      ast = {:{}, [line: 1], [1, 2, 3]}

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  test "variable" do
    # my_var
    ast = {:my_var, [line: 1], nil}

    assert transform(ast, %Context{}) == %IR.Variable{name: :my_var}
  end
end
