defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Component

  alias Hologram.Component
  alias Hologram.Component.Action
  alias Hologram.Component.Command
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Server.Broadcast
  alias Hologram.Test.Fixtures.Component.Module1
  alias Hologram.Test.Fixtures.Component.Module2
  alias Hologram.Test.Fixtures.Component.Module3
  alias Hologram.Test.Fixtures.Component.Module36
  alias Hologram.Test.Fixtures.Component.Module4
  alias Hologram.Test.Fixtures.Component.Module5
  alias Hologram.Test.Fixtures.Component.Module7
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  @server %Server{cid: "page"}

  describe "__derived__/0" do
    test "lists the derived fields in the order they can be computed" do
      assert Module36.__derived__() == [
               %{
                 args: [:first_name, :last_name],
                 function: &Module36.__derived_full_name__/2,
                 name: :full_name,
                 reads_state: false,
                 type: :string
               },
               %{
                 args: [:full_name, :shout],
                 function: &Module36.__derived_greeting__/2,
                 name: :greeting,
                 reads_state: true,
                 type: :string
               },
               %{
                 args: [],
                 function: &Module36.__derived_motto__/0,
                 name: :motto,
                 reads_state: false,
                 type: :string
               }
             ]
    end

    test "lists no derived fields for a component declaring none" do
      assert Module4.__derived__() == []
    end

    test "holds each derived field's function" do
      assert Module36.__derived_greeting__("Ada Lovelace", true) == "HI ADA LOVELACE"
    end

    test "holds the function a zero-arity capture stands for" do
      assert Module36.__derived_motto__() == "Hello"
    end
  end

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  test "__props__/0" do
    assert Module4.__props__() == [{:a, :string, []}, {:b, :integer, [default: 222]}]
  end

  test "__state__/0" do
    assert Module7.__state__() == [
             {:count, :integer, [default: 0]},
             {:user, :map, []}
           ]
  end

  test "colocated_template_path/1" do
    assert colocated_template_path("/my_dir_1/my_dir_2/my_dir_3/my_file.ex") ==
             "/my_dir_1/my_dir_2/my_dir_3/my_file.holo"
  end

  describe "delete_subscription/2" do
    test "removes {channel, server.cid} from server.subscriptions" do
      result =
        @server
        |> put_subscription(:room_a)
        |> delete_subscription(:room_a)

      assert result.subscriptions == []
    end

    test "leaves bindings for other cids intact (encapsulation)" do
      server_with_layout_binding = %{@server | subscriptions: [{:room_a, "layout"}]}

      result = delete_subscription(server_with_layout_binding, :room_a)

      assert result.subscriptions == [{:room_a, "layout"}]
    end

    test "records :delete in subscription_ops keyed by {channel, server.cid}" do
      result = delete_subscription(@server, :room_a)

      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :delete}
    end

    test "records :delete even when {channel, cid} is not present in server.subscriptions" do
      result = delete_subscription(@server, :room_a)

      assert result.subscriptions == []
      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :delete}
    end

    test "raises ArgumentError for an invalid channel" do
      assert_raise ArgumentError, fn -> delete_subscription(@server, "not_a_valid_channel") end
    end
  end

  describe "derived/3" do
    test "stands a capture of a zero-arity function of another module for the function calling it" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedRemoteCapture do
          use Hologram.Component

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          derived :entities, [Entity2], &Hologram.Test.Fixtures.Component.Module9.shared_query/0

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() == filter(Entity2, a: true)
    end

    test "reads a bare name inside a query as the queried row's" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedRowName do
          use Hologram.Component
          use Hologram.DB

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> filter(Entity2, b == true) end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() == filter(Entity2, b == true)
    end

    test "reads a bare name inside a piped query as the queried row's" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedPipedRowName do
          use Hologram.Component
          use Hologram.DB

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> Entity2 |> filter(b == true) |> sort(b) end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() ==
               Entity2
               |> filter(b == true)
               |> sort(b)
    end

    test "reads a bare name inside a query through an alias of Hologram.Query as the queried row's" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedAliasedRowName do
          use Hologram.Component

          require Hologram.Query, as: Q

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> Q.filter(Entity2, b == true) end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() == filter(Entity2, b == true)
    end

    test "reads a bare name inside a query macro the body imports as the queried row's" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedBodyImport do
          use Hologram.Component

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn ->
            import Hologram.Query, only: [filter: 2]

            filter(Entity2, b == true)
          end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() == filter(Entity2, b == true)
    end

    test "reads a bare name inside a query through an alias the body declares as the queried row's" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedBodyAlias do
          use Hologram.Component

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn ->
            require Hologram.Query, as: Q

            Q.filter(Entity2, b == true)
          end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_entities__() == filter(Entity2, b == true)
    end

    test "reads a capture of a function named like a prop as no variable" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedCaptureNamedLikeProp do
          use Hologram.Component

          prop :label, :string
          prop :items, :list

          derived :labels, :list, fn items -> Enum.map(items, &label/1) end

          def template do
            ~HOLO""
          end

          defp label(item), do: "#\{item}!"
        end
        """)

      assert module.__derived_labels__([1, 2]) == ["1!", "2!"]
    end

    test "reads a bitstring type specifier named like a prop as no variable" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedSpecifierNamedLikeProp do
          use Hologram.Component

          prop :binary, :string
          prop :text, :string

          derived :initial, :string, fn text ->
            <<first::binary-size(1), _rest::binary>> = text
            first
          end

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_initial__("Ada") == "A"
    end

    test "reads a module attribute's value at the declaration" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedAttributeAtLine do
          use Hologram.Component

          @limit 1

          derived :limit, :integer, fn -> @limit end

          @limit 2

          def later_limit, do: @limit

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__derived_limit__() == 1
    end

    test "counts an alias the body reads as used" do
      {_result, diagnostics} =
        Code.with_diagnostics(fn ->
          Code.eval_string("""
          defmodule Hologram.Test.Fixtures.Component.DerivedAliasInBody do
            use Hologram.Component

            alias Hologram.Test.Fixtures.Component.Module9

            derived :entities, :list, fn -> Module9.shared_query() end

            def template do
              ~HOLO""
            end
          end
          """)
        end)

      assert diagnostics == []
    end

    test "marks a derived field reading state through another derived field as reading state" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedStateThroughField do
          use Hologram.Component

          state :step, :integer, default: 1

          derived :double, :integer, fn step -> step * 2 end
          derived :quadruple, :integer, fn double -> double * 2 end

          def template do
            ~HOLO""
          end
        end
        """)

      assert Enum.map(module.__derived__(), &{&1.name, &1.reads_state}) == [
               double: true,
               quadruple: true
             ]
    end

    test "raises on a name that is not an atom" do
      expected_msg =
        "nofile:4: the name of derived field \"total\" in Hologram.Test.Fixtures.Component.DerivedStringName must be an atom"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedStringName do
          use Hologram.Component

          derived "total", :integer, fn -> 1 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a function with a guard" do
      expected_msg =
        "nofile:6: the function of derived field :double in Hologram.Test.Fixtures.Component.DerivedGuard takes no guard, got: when is_integer(count) - its arguments name the fields it reads"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedGuard do
          use Hologram.Component

          prop :count, :integer

          derived :double, :integer, fn count when is_integer(count) -> count * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a function with two clauses" do
      expected_msg =
        "nofile:6: the function of derived field :double in Hologram.Test.Fixtures.Component.DerivedTwoClauses has 2 clauses - a derived field's function has one clause, since its head names the fields it reads"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedTwoClauses do
          use Hologram.Component

          prop :count, :integer

          derived :double, :integer, fn
            0 -> 0
            count -> count * 2
          end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a definition that is no function" do
      expected_msg =
        "nofile:4: derived field :double in Hologram.Test.Fixtures.Component.DerivedNoFunction is defined by a function whose arguments name the fields it reads, got: 2 - write it as fn fields -> ... end, calling a shared query builder from the body if one computes it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedNoFunction do
          use Hologram.Component

          derived :double, :integer, 2

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on the capture shorthand" do
      expected_msg =
        "nofile:6: derived field :double in Hologram.Test.Fixtures.Component.DerivedShorthand is defined by a function whose arguments name the fields it reads, got: &(&1 * 2) - write it as fn fields -> ... end, calling a shared query builder from the body if one computes it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedShorthand do
          use Hologram.Component

          prop :count, :integer

          derived :double, :integer, &(&1 * 2)

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on an argument that is a pattern" do
      expected_msg =
        "nofile:6: the arguments of derived field :total in Hologram.Test.Fixtures.Component.DerivedPatternArgument's function name fields, each a bare name, got: %{count: count} - a pattern, a default or the underscore has no field to name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedPatternArgument do
          use Hologram.Component

          prop :count, :integer

          derived :total, :integer, fn %{count: count} -> count end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on an underscore argument" do
      expected_msg =
        "nofile:4: the arguments of derived field :total in Hologram.Test.Fixtures.Component.DerivedUnderscoreArgument's function name fields, each a bare name, got: _ - a pattern, a default or the underscore has no field to name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnderscoreArgument do
          use Hologram.Component

          derived :total, :integer, fn _ -> 1 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on an argument named twice" do
      expected_msg =
        "nofile:6: count is named twice in the head of derived field :total in Hologram.Test.Fixtures.Component.DerivedRepeatedArgument's function - each argument names a field once"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedRepeatedArgument do
          use Hologram.Component

          prop :count, :integer

          derived :total, :integer, fn count, count -> count end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a capture of a function with arguments" do
      expected_msg =
        "nofile:6: derived field :double in Hologram.Test.Fixtures.Component.DerivedCaptureWithArguments is a capture of double/1, which hides the fields it reads - write fn ... -> double(...) end, naming them in the head"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedCaptureWithArguments do
          use Hologram.Component

          prop :count, :integer

          derived :double, :integer, &double/1

          def template do
            ~HOLO""
          end

          defp double(count), do: count * 2
        end
        """)
      end
    end

    test "raises on a head naming what is no field" do
      expected_msg =
        "nofile:8: total is not a field of Hologram.Test.Fixtures.Component.DerivedUnknownName - the arguments of derived field :double's function name the fields it reads: count, step"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnknownName do
          use Hologram.Component

          prop :count, :integer

          state :step, :integer

          derived :double, :integer, fn total -> total * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a head naming a field of a component declaring none" do
      expected_msg =
        "nofile:4: total is not a field of Hologram.Test.Fixtures.Component.DerivedNothingToRead - the arguments of derived field :double's function name the fields it reads, and Hologram.Test.Fixtures.Component.DerivedNothingToRead declares none"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedNothingToRead do
          use Hologram.Component

          derived :double, :integer, fn total -> total * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a head naming its own field" do
      expected_msg =
        "nofile:4: derived field :double in Hologram.Test.Fixtures.Component.DerivedSelfRead reads itself - a derived field is computed from other fields"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedSelfRead do
          use Hologram.Component

          derived :double, :integer, fn double -> double * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on derived fields reading each other in a cycle" do
      expected_msg =
        "nofile:6: derived fields in Hologram.Test.Fixtures.Component.DerivedCycle read each other in a cycle: :a, :b"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedCycle do
          use Hologram.Component

          prop :count, :integer

          derived :a, :integer, fn b -> b end
          derived :b, :integer, fn a -> a end
          derived :c, :integer, fn count -> count end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a cycle naming its fields only, not a field reading it" do
      expected_msg =
        "nofile:5: derived fields in Hologram.Test.Fixtures.Component.DerivedCycleReader read each other in a cycle: :a, :b"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedCycleReader do
          use Hologram.Component

          derived :c, :integer, fn a -> a end
          derived :a, :integer, fn b -> b end
          derived :b, :integer, fn a -> a end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on the first of two cycles" do
      expected_msg =
        "nofile:4: derived fields in Hologram.Test.Fixtures.Component.DerivedTwoCycles read each other in a cycle: :a, :b"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedTwoCycles do
          use Hologram.Component

          derived :a, :integer, fn b -> b end
          derived :b, :integer, fn a -> a end
          derived :x, :integer, fn y -> y end
          derived :y, :integer, fn x -> x end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a name a prop declares" do
      expected_msg =
        "nofile:4: derived field :count in Hologram.Test.Fixtures.Component.DerivedPropName has the same name as a prop, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedPropName do
          use Hologram.Component

          derived :count, :integer, fn -> 1 end

          prop :count, :integer

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a name a state entry declares" do
      expected_msg =
        "nofile:6: derived field :count in Hologram.Test.Fixtures.Component.DerivedStateName has the same name as a state entry, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedStateName do
          use Hologram.Component

          state :count, :integer

          derived :count, :integer, fn -> 1 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on the name of the cid prop" do
      expected_msg =
        "nofile:4: derived field :cid in Hologram.Test.Fixtures.Component.DerivedCidName has the same name as the cid prop, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedCidName do
          use Hologram.Component

          derived :cid, :string, fn -> "x" end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a name another derived field declares" do
      expected_msg =
        "nofile:5: derived field :total in Hologram.Test.Fixtures.Component.DerivedRepeatedName has the same name as another derived field, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedRepeatedName do
          use Hologram.Component

          derived :total, :integer, fn -> 1 end
          derived :total, :integer, fn -> 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body reading a prop its head doesn't name" do
      expected_msg =
        "nofile:7: step is a prop of Hologram.Test.Fixtures.Component.DerivedUnnamedRead, which derived field :total's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnnamedRead do
          use Hologram.Component

          prop :count, :integer
          prop :step, :integer

          derived :total, :integer, fn count -> count + step end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body reading a derived field its head doesn't name" do
      expected_msg =
        "nofile:7: double is a derived field of Hologram.Test.Fixtures.Component.DerivedUnnamedField, which derived field :total's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnnamedField do
          use Hologram.Component

          prop :count, :integer

          derived :double, :integer, fn count -> count * 2 end
          derived :total, :integer, fn count -> count + double end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body reading its own field" do
      expected_msg =
        "nofile:6: derived field :total in Hologram.Test.Fixtures.Component.DerivedOwnNameRead reads itself - a derived field is computed from other fields"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedOwnNameRead do
          use Hologram.Component

          prop :count, :integer

          derived :total, :integer, fn count -> count + total end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body binding a local named like a state entry" do
      expected_msg =
        "nofile:6: step is a state entry of Hologram.Test.Fixtures.Component.DerivedShadowingLocal, so derived field :total's function can't bind a local of that name - give the local another name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedShadowingLocal do
          use Hologram.Component

          state :step, :integer

          derived :total, :integer, fn ->
            step = 2
            step * 2
          end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body binding a local named like its own field" do
      expected_msg =
        "nofile:4: total is the name of derived field :total in Hologram.Test.Fixtures.Component.DerivedOwnNameLocal, so its function can't bind a local of that name - give the local another name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedOwnNameLocal do
          use Hologram.Component

          derived :total, :integer, fn ->
            total = 2
            total * 2
          end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a query pinning a prop its head doesn't name" do
      expected_msg =
        "nofile:9: b is a prop of Hologram.Test.Fixtures.Component.DerivedUnnamedPin, which derived field :entities's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnnamedPin do
          use Hologram.Component
          use Hologram.DB

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> filter(Entity2, b == ^b) end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a piped query pinning a prop its head doesn't name" do
      expected_msg =
        "nofile:9: b is a prop of Hologram.Test.Fixtures.Component.DerivedUnnamedPipedPin, which derived field :entities's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnnamedPipedPin do
          use Hologram.Component
          use Hologram.DB

          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> Entity2 |> filter(b == ^b) end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a qualified query macro pinning a prop its head doesn't name" do
      expected_msg =
        "nofile:9: b is a prop of Hologram.Test.Fixtures.Component.DerivedUnnamedQualifiedPin, which derived field :entities's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedUnnamedQualifiedPin do
          use Hologram.Component

          alias Hologram.Query
          alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

          prop :b, :string

          derived :entities, [Entity2], fn -> Query.filter(Entity2, b == ^b) end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a prop its head doesn't name passed to a function of the component's own named like a query macro" do
      expected_msg =
        "nofile:6: b is a prop of Hologram.Test.Fixtures.Component.DerivedOwnFilter, which derived field :total's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DerivedOwnFilter do
          use Hologram.Component

          prop :b, :integer

          derived :total, :integer, fn -> filter(1, b) end

          def template do
            ~HOLO""
          end

          defp filter(left, right), do: left + right
        end
        """)
      end
    end
  end

  describe "init/2" do
    test "default implementation" do
      assert Reflection.has_function?(Module1, :init, 2)

      component = build_component_struct()
      assert Module1.init(:props_dummy, component) == component
    end

    test "overridden implementation" do
      assert Module2.init(:props_dummy, build_component_struct()) == %Component{
               state: %{overriden: true}
             }
    end
  end

  describe "init/3" do
    test "default implementation" do
      assert Reflection.has_function?(Module1, :init, 3)
    end

    test "overridden implementation" do
      assert Module2.init(:props_dummy, build_component_struct(), build_server_struct()) ==
               {%Component{state: %{overriden: true}}, %Server{}}
    end
  end

  describe "maybe_register_colocated_template_markup/1" do
    test "valid template path" do
      template_path = "#{@fixtures_dir}/component/template_7.holo"

      assert maybe_register_colocated_template_markup(template_path) ==
               {:@, [context: Hologram.Component, imports: [{1, Kernel}]],
                [
                  {:__colocated_template_markup__, [context: Hologram.Component],
                   ["My template 7"]}
                ]}
    end

    test "invalid template path" do
      refute maybe_register_colocated_template_markup("/my_invalid_template_path.holo")
    end
  end

  describe "prop/3" do
    test "accepts the supported options" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.SupportedPropOpts do
          use Hologram.Component

          prop :a, :string
          prop :b, :string, default: "abc"
          prop :c, :string, from_context: :my_context_key
          prop :d, :string, required: true
          prop :e, :string, values: ["abc", "xyz"]

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [
               {:a, :string, []},
               {:b, :string, [default: "abc"]},
               {:c, :string, [from_context: :my_context_key]},
               {:d, :string, [required: true]},
               {:e, :string, [values: ["abc", "xyz"]]}
             ]
    end

    test "raises when an option is not supported" do
      expected_error_msg =
        ~s/invalid option :some_option for prop "b" in Hologram.Test.Fixtures.Component.UnsupportedPropOpt, expected one of: :default, :from_context, :required, :values/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.UnsupportedPropOpt do
          use Hologram.Component

          prop :b, :string, some_option: "abc"

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the :required option is not a boolean" do
      expected_error_msg =
        ~s/the :required option for prop "b" in Hologram.Test.Fixtures.Component.NonBooleanRequiredOpt / <>
          ~s/must be a boolean, got: "yes"/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonBooleanRequiredOpt do
          use Hologram.Component

          prop :b, :string, required: "yes"

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the :values option is not a list" do
      expected_error_msg =
        ~s/the :values option for prop "b" in Hologram.Test.Fixtures.Component.NonListValuesOpt / <>
          "must be a list, got: :abc"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonListValuesOpt do
          use Hologram.Component

          prop :b, :string, values: :abc

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when a prop is both required and has a default value" do
      expected_error_msg =
        ~s/prop "b" in Hologram.Test.Fixtures.Component.RequiredPropWithDefault / <>
          "can't be both required and have a default value"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.RequiredPropWithDefault do
          use Hologram.Component

          prop :b, :string, required: true, default: "abc"

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the default value is not in the :values list" do
      expected_error_msg =
        ~s/the :default value :medium for prop "b" in Hologram.Test.Fixtures.Component.DefaultOutsideValues / <>
          "is not one of [:small, :large]"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DefaultOutsideValues do
          use Hologram.Component

          prop :b, :atom, values: [:small, :large], default: :medium

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "accepts a default value that is in the :values list" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DefaultInsideValues do
          use Hologram.Component

          prop :b, :atom, values: [:small, :large], default: :small

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:b, :atom, [values: [:small, :large], default: :small]}]
    end

    test "raises when a composite default value is not in the :values list" do
      expected_error_msg =
        ~s/the :default value [:c] for prop "b" in Hologram.Test.Fixtures.Component.CompositeDefaultOutsideValues / <>
          "is not one of [[:a], [:b]]"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.CompositeDefaultOutsideValues do
          use Hologram.Component

          prop :b, :list, values: [[:a], [:b]], default: [:c]

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    # The same map has more than one AST form, so the comparison has to be made on evaluated terms.
    test "accepts a map default whose key order differs from the :values entry" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.MapDefaultInValues do
          use Hologram.Component

          prop :b, :map, values: [%{a: 1, b: 2}], default: %{b: 2, a: 1}

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:b, :map, [values: [%{a: 1, b: 2}], default: %{b: 2, a: 1}]}]
    end

    # A struct literal can't be resolved without calling its __struct__/1, on a module that may not
    # be compiled yet, so it is left to the render-time check rather than compared here.
    test "accepts a struct default value without judging it" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.StructDefaultOutsideValues do
          use Hologram.Component

          prop :b, :struct, values: [%Range{first: 1, last: 2, step: 1}], default: 1..3

          def template do
            ~HOLO""
          end
        end
        """)

      assert [{:b, :struct, opts}] = module.__props__()
      assert opts[:default] == 1..3
    end

    test "accepts a required prop sourced from context" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.RequiredPropFromContext do
          use Hologram.Component

          prop :b, :string, required: true, from_context: :my_context_key

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [
               {:b, :string, [required: true, from_context: :my_context_key]}
             ]
    end

    test "accepts required: false combined with a default value" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NotRequiredPropWithDefault do
          use Hologram.Component

          prop :b, :string, required: false, default: "abc"

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:b, :string, [required: false, default: "abc"]}]
    end

    test "raises when the options are a literal that is not a list" do
      expected_error_msg =
        ~s/the options for prop "b" in Hologram.Test.Fixtures.Component.NonListPropOpts / <>
          "must be a keyword list, got: :values"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonListPropOpts do
          use Hologram.Component

          prop :b, :string, :values

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when a literal option entry is not a key/value pair" do
      expected_error_msg =
        ~s/invalid option {"values", [:small]} for prop "b" in / <>
          "Hologram.Test.Fixtures.Component.MalformedPropOptEntry, " <>
          "options must be given as a keyword list"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.MalformedPropOptEntry do
          use Hologram.Component

          prop :b, :string, [{"values", [:small]}]

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "doesn't raise when an option value is not a literal" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonLiteralRequiredOptValue do
          use Hologram.Component

          @my_flag "not a boolean"

          prop :b, :string, required: @my_flag

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:b, :string, [required: "not a boolean"]}]
    end

    test "doesn't raise when the options are not a literal keyword list" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonLiteralPropOpts do
          use Hologram.Component

          @my_opts [default: "abc"]

          prop :a, :string, @my_opts

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:a, :string, [default: "abc"]}]
    end

    test "raises on a from_query option, which derived fields replaced" do
      code = ~s'''
      defmodule Hologram.ComponentTest.FromQueryFixture do
        use Hologram.Component

        alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

        prop :entities, [Entity2], from_query: &Hologram.Test.Fixtures.Component.Module9.shared_query/0

        @impl Component
        def template do
          ~HOLO""
        end
      end
      '''

      expected_msg =
        ~s/invalid option :from_query for prop "entities" in Hologram.ComponentTest.FromQueryFixture, expected one of: :default, :from_context, :required, :values/

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code)
      end
    end
  end

  describe "put_action/2, component struct" do
    test "name" do
      result = put_action(%Component{}, :my_action)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_action(%Component{}, name: :my_action)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_action(%Component{}, params: [a: 1, b: 2])

      assert result == %Component{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_action(%Component{}, target: "my_target")

      assert result == %Component{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end

    test "spec: delay" do
      result = put_action(%Component{}, delay: 500)

      assert result == %Component{
               next_action: %Action{name: nil, params: %{}, target: nil, delay: 500}
             }
    end

    test "spec: name, params, target, delay" do
      result =
        put_action(%Component{},
          name: :my_action,
          params: [a: 1, b: 2],
          target: "my_target",
          delay: 500
        )

      assert result == %Component{
               next_action: %Action{
                 name: :my_action,
                 params: %{a: 1, b: 2},
                 target: "my_target",
                 delay: 500
               }
             }
    end
  end

  describe "put_action/2, server struct" do
    test "name" do
      result = put_action(%Server{}, :my_action)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_action(%Server{}, name: :my_action)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_action(%Server{}, params: [a: 1, b: 2])

      assert result == %Server{
               next_action: %Action{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_action(%Server{}, target: "my_target")

      assert result == %Server{
               next_action: %Action{name: nil, target: "my_target", params: %{}}
             }
    end

    test "spec: delay" do
      result = put_action(%Server{}, delay: 750)

      assert result == %Server{
               next_action: %Action{name: nil, params: %{}, target: nil, delay: 750}
             }
    end

    test "spec: name, params, target, delay" do
      result =
        put_action(%Server{},
          name: :my_action,
          params: [a: 1, b: 2],
          target: "my_target",
          delay: 750
        )

      assert result == %Server{
               next_action: %Action{
                 name: :my_action,
                 params: %{a: 1, b: 2},
                 target: "my_target",
                 delay: 750
               }
             }
    end
  end

  describe "put_action/3, component struct" do
    test "accepts params as keyword list" do
      result = put_action(%Component{}, :my_action, a: 1, b: 2)

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_action(%Component{}, :my_action, %{a: 1, b: 2})

      assert result == %Component{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end
  end

  describe "put_action/3, server struct" do
    test "accepts params as keyword list" do
      result = put_action(%Server{}, :my_action, a: 1, b: 2)

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_action(%Server{}, :my_action, %{a: 1, b: 2})

      assert result == %Server{
               next_action: %Action{name: :my_action, params: %{a: 1, b: 2}, target: nil}
             }
    end
  end

  describe "put_broadcast/* (common behavior)" do
    test "prepends so multiple calls accumulate in reverse-of-call order" do
      result =
        @server
        |> put_broadcast({:room, 1}, :first)
        |> put_broadcast({:room, 2}, :second)

      assert result.broadcasts == [
               %Broadcast{channel: {:room, 2}, action_name: :second, params: %{}},
               %Broadcast{channel: {:room, 1}, action_name: :first, params: %{}}
             ]
    end

    test "raises at the call site when the channel is invalid" do
      assert_error ArgumentError,
                   ~s(a channel must be an identifier, like :search or {:message, 42}, got: "bad-channel"),
                   fn -> put_broadcast(@server, "bad-channel", :foo) end
    end
  end

  describe "put_broadcast/3" do
    test "defaults params to an empty map" do
      result = put_broadcast(@server, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{channel: {:room, 42}, action_name: :refresh, params: %{}}
             ]
    end
  end

  describe "put_broadcast/4" do
    test "accepts params as a keyword list" do
      result = put_broadcast(@server, {:room, 42}, :append_message, text: "hi")

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :append_message,
                 params: %{text: "hi"}
               }
             ]
    end

    test "accepts params as a map" do
      result = put_broadcast(@server, {:room, 42}, :append_message, %{text: "hi"})

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :append_message,
                 params: %{text: "hi"}
               }
             ]
    end
  end

  describe "put_broadcast_except/* (common behavior)" do
    # Tests here cover what's shared across all put_broadcast_except arities:
    # the single-tuple-vs-list normalization on except, and validator wiring.
    # Per-arity tests below focus on the params dispatch surface.

    test "wraps a single identity tuple into a list and stores on except" do
      result = put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]
    end

    test "stores a list of identities unchanged on except" do
      except = [{:user, "u1"}, {:session, "s1"}, {:instance, "i1"}]

      result = put_broadcast_except(@server, except, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :refresh,
                 params: %{},
                 except: except
               }
             ]
    end

    test "raises at the call site when the channel is invalid" do
      assert_error ArgumentError,
                   ~s(a channel must be an identifier, like :search or {:message, 42}, got: "bad-channel"),
                   fn -> put_broadcast_except(@server, {:user, "u1"}, "bad-channel", :foo) end
    end
  end

  describe "put_broadcast_except/4" do
    test "defaults params to an empty map" do
      result = put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, :refresh)

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :refresh,
                 params: %{},
                 except: [{:user, "u1"}]
               }
             ]
    end
  end

  describe "put_broadcast_except/5" do
    test "accepts params as a keyword list" do
      result =
        put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, :append_message, text: "hi")

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :append_message,
                 params: %{text: "hi"},
                 except: [{:user, "u1"}]
               }
             ]
    end

    test "accepts params as a map" do
      result =
        put_broadcast_except(@server, {:user, "u1"}, {:room, 42}, :append_message, %{text: "hi"})

      assert result.broadcasts == [
               %Broadcast{
                 channel: {:room, 42},
                 action_name: :append_message,
                 params: %{text: "hi"},
                 except: [{:user, "u1"}]
               }
             ]
    end
  end

  describe "put_command/2" do
    test "name" do
      result = put_command(%Component{}, :my_command)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: name" do
      result = put_command(%Component{}, name: :my_command)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{}, target: nil}
             }
    end

    test "spec: params" do
      result = put_command(%Component{}, params: [a: 1, b: 2])

      assert result == %Component{
               next_command: %Command{name: nil, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "spec: target" do
      result = put_command(%Component{}, target: "my_target")

      assert result == %Component{
               next_command: %Command{name: nil, target: "my_target", params: %{}}
             }
    end
  end

  describe "put_command/3" do
    test "accepts params as keyword list" do
      result = put_command(%Component{}, :my_command, a: 1, b: 2)

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{a: 1, b: 2}, target: nil}
             }
    end

    test "accepts params as a map" do
      result = put_command(%Component{}, :my_command, %{a: 1, b: 2})

      assert result == %Component{
               next_command: %Command{name: :my_command, params: %{a: 1, b: 2}, target: nil}
             }
    end
  end

  test "put_context/3" do
    component = %Component{emitted_context: %{a: 1}}

    assert put_context(component, :b, 2) == %Component{
             emitted_context: %{a: 1, b: 2}
           }
  end

  test "put_page/2" do
    assert put_page(%Component{}, MyPage) == %Component{next_page: MyPage}
  end

  test "put_page/3" do
    assert put_page(%Component{}, MyPage, a: 1, b: 2) == %Component{
             next_page: {MyPage, a: 1, b: 2}
           }
  end

  describe "put_state/2" do
    test "keyword" do
      component = %Component{state: %{a: 1}}

      assert put_state(component, b: 2, c: 3) == %Component{
               state: %{a: 1, b: 2, c: 3}
             }
    end

    test "map" do
      component = %Component{state: %{a: 1}}

      assert put_state(component, %{b: 2, c: 3}) == %Component{
               state: %{a: 1, b: 2, c: 3}
             }
    end
  end

  describe "put_state/3" do
    test "non-nested path" do
      component = %Component{state: %{a: 1, b: 2}}
      result = put_state(component, :b, 3)

      assert result == %Component{
               state: %{a: 1, b: 3}
             }
    end

    test "nested path, map" do
      component = %Component{state: %{a: 1, b: %{c: 2, d: 3}}}
      result = put_state(component, [:b, :d], 4)

      assert result == %Component{state: %{a: 1, b: %{c: 2, d: 4}}}
    end

    test "nested path, struct" do
      component = %Component{state: %{a: 1, b: %Module5{x: 2, y: 3}}}
      result = put_state(component, [:b, :y], 4)

      assert result == %Component{state: %{a: 1, b: %Module5{x: 2, y: 4}}}
    end
  end

  describe "put_subscription/2" do
    test "appends {channel, server.cid} to server.subscriptions" do
      result = put_subscription(@server, :room_a)

      assert result.subscriptions == [{:room_a, "page"}]
    end

    test "records :put in subscription_ops keyed by {channel, server.cid}" do
      result = put_subscription(@server, :room_a)

      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :put}
    end

    test "server.subscriptions and __meta__.subscription_ops stay in sync across multiple calls" do
      result =
        @server
        |> put_subscription(:room_a)
        |> put_subscription(:room_b)

      assert MapSet.new(result.subscriptions) ==
               MapSet.new([{:room_a, "page"}, {:room_b, "page"}])

      assert result.__meta__.subscription_ops == %{
               {:room_a, "page"} => :put,
               {:room_b, "page"} => :put
             }
    end

    test "deduplicates when the same {channel, cid} key is put again" do
      result =
        @server
        |> put_subscription(:room_a)
        |> put_subscription(:room_a)

      assert result.subscriptions == [{:room_a, "page"}]
      assert result.__meta__.subscription_ops == %{{:room_a, "page"} => :put}
    end

    test "raises ArgumentError for an invalid channel" do
      assert_raise ArgumentError, fn -> put_subscription(@server, "not_a_valid_channel") end
    end
  end

  describe "state/3" do
    test "accepts the supported options" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.SupportedStateOpts do
          use Hologram.Component

          state :a, :string
          state :b, :string, default: "abc"

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__state__() == [
               {:a, :string, []},
               {:b, :string, [default: "abc"]}
             ]
    end

    test "accepts a prop declared after a state entry with another name" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.StateBeforeProp do
          use Hologram.Component

          state :count, :integer, default: 0

          prop :label, :string

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__props__() == [{:label, :string, []}]
      assert module.__state__() == [{:count, :integer, [default: 0]}]
    end

    test "accepts options given as an expression" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.ExpressionStateOpts do
          use Hologram.Component

          @my_opts [default: ""]

          state :a, :string, @my_opts

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__state__() == [{:a, :string, [default: ""]}]
    end

    test "raises when an option is not supported" do
      expected_error_msg =
        ~s/invalid option :some_option for state "b" in Hologram.Test.Fixtures.Component.UnsupportedStateOpt, expected one of: :default/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.UnsupportedStateOpt do
          use Hologram.Component

          state :b, :string, some_option: "abc"

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when an option given as an expression is not supported" do
      expected_error_msg =
        ~s/invalid option :some_option for state "b" in Hologram.Test.Fixtures.Component.UnsupportedExpressionStateOpt, expected one of: :default/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.UnsupportedExpressionStateOpt do
          use Hologram.Component

          @my_opts [some_option: "abc"]

          state :b, :string, @my_opts

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the options are not a keyword list" do
      expected_error_msg =
        ~s/the options for state "b" in Hologram.Test.Fixtures.Component.NonKeywordStateOpts / <>
          ~s/must be a keyword list, got: [{"default", 1}]/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonKeywordStateOpts do
          use Hologram.Component

          state :b, :integer, [{"default", 1}]

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when an option is given more than once" do
      expected_error_msg =
        ~s/option :default is given more than once for state "b" / <>
          "in Hologram.Test.Fixtures.Component.RepeatedStateOpt"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.RepeatedStateOpt do
          use Hologram.Component

          state :b, :integer, default: 1, default: 2

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the name is not an atom" do
      expected_error_msg =
        ~s/the name of state "b" in Hologram.Test.Fixtures.Component.NonAtomStateName must be an atom/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.NonAtomStateName do
          use Hologram.Component

          state "b", :integer, default: 0

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when an entry is declared more than once" do
      expected_error_msg =
        ~s/state "b" is declared more than once in Hologram.Test.Fixtures.Component.DuplicateState/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.DuplicateState do
          use Hologram.Component

          state :a, :string
          state :b, :string
          state :b, :integer

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises at the state entry when it has the same name as a prop declared before it" do
      code = """
      defmodule Hologram.Test.Fixtures.Component.StateClashLineAfterProp do
        use Hologram.Component

        prop :items, :list

        state :items, :list, default: []

        def template do
          ~HOLO""
        end
      end
      """

      expected_error_msg =
        ~s/state "items" in Hologram.Test.Fixtures.Component.StateClashLineAfterProp has the same name as a prop, / <>
          "which it would shadow - give them different names"

      assert compile_error_at(code) == {expected_error_msg, 6}
    end

    test "raises at the prop when it has the same name as a state entry declared before it" do
      code = """
      defmodule Hologram.Test.Fixtures.Component.StateClashLineBeforeProp do
        use Hologram.Component

        state :items, :list, default: []

        prop :items, :list

        def template do
          ~HOLO""
        end
      end
      """

      expected_error_msg =
        ~s/state "items" in Hologram.Test.Fixtures.Component.StateClashLineBeforeProp has the same name as a prop, / <>
          "which it would shadow - give them different names"

      assert compile_error_at(code) == {expected_error_msg, 6}
    end

    test "raises when an entry has the same name as a prop sourced from context" do
      expected_error_msg =
        ~s/state "user" in Hologram.Test.Fixtures.Component.StateNamedLikeContextProp has the same name as a prop, / <>
          "which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.StateNamedLikeContextProp do
          use Hologram.Component

          prop :user, :map, from_context: :current_user

          state :user, :map

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when an entry is named cid" do
      expected_error_msg =
        ~s/state "cid" in Hologram.Test.Fixtures.Component.StateNamedCid has the same name as the cid prop, / <>
          "which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Component.StateNamedCid do
          use Hologram.Component

          state :cid, :string, default: "my_cid"

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end
  end

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      result = Module3.template().(%{})

      assert [
               {:text, text},
               {:component, Hologram.UI.Link,
                [{"to", [expression: {Hologram.Test.Fixtures.Component.Module6}]}],
                [text: "Module6"]}
             ] = result

      assert normalize_newlines(text) == "Module3 template\n"
    end
  end
end
