defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module2

  describe "validate_model!/1" do
    test "returns :ok for empty model" do
      assert validate_model!([]) == :ok
    end

    test "returns :ok for entity types without policy declarations" do
      assert validate_model!([Module1, Module2]) == :ok
    end

    test "returns :ok for every declared predicate value kind" do
      defmodule InlinePolicyFixture1 do
        use Hologram.Entity

        attribute :count, :integer
        attribute :status, :enum, values: [:done, :todo]
        attribute :title, :string

        allow :read, status: :done
        allow :publish, count: {:>=, 3}
        allow :triage, status: [:done, :todo]
        allow :archive, count: 1..10
        allow :unlink, title: {:!=, nil}
      end

      assert validate_model!([InlinePolicyFixture1]) == :ok
    end

    test "returns :ok for a predicate on a to-one reference field" do
      assert validate_model!([Module13]) == :ok
    end

    test "returns :ok for bare allow lines" do
      defmodule InlinePolicyFixture2 do
        use Hologram.Entity

        relationship :parent, Module1

        role :owner

        allow :read
        allow :update, to: :owner
        allow :publish, via: :parent
      end

      assert validate_model!([InlinePolicyFixture2]) == :ok
    end

    test "returns :ok for actor leaves on uuid-carrying names" do
      defmodule InlinePolicyFixture7 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, id: user_id()
        allow :update, parent_id: {:!=, user_id()}
      end

      assert validate_model!([InlinePolicyFixture7]) == :ok
    end

    test "rejects an actor leaf on a non-uuid attribute" do
      defmodule InlinePolicyFixture8 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, title: user_id()
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture8 - user_id() requires a uuid attribute - attribute :title in Hologram.PolicyTest.InlinePolicyFixture8 has type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture8])
      end
    end

    test "rejects a predicate naming an unknown attribute" do
      defmodule InlinePolicyFixture3 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, published: true
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture3 - unknown attribute :published in Hologram.PolicyTest.InlinePolicyFixture3 - known attributes: :created_at, :id, :title, :updated_at"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture3])
      end
    end

    test "rejects a predicate naming a relationship" do
      defmodule InlinePolicyFixture4 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, parent: nil
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture4 - :parent is a relationship in Hologram.PolicyTest.InlinePolicyFixture4 - only attributes can be filtered - filter its reference via :parent_id"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture4])
      end
    end

    test "rejects a predicate using an unknown operator" do
      defmodule InlinePolicyFixture5 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, title: {:like, "text_1"}
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture5 - unknown operator :like in the filter predicate for attribute :title - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture5])
      end
    end

    test "rejects an ordering comparison on a to-one reference field" do
      defmodule InlinePolicyFixture6 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, parent_id: {:>=, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture6 - operator :>= requires a numeric or temporal attribute - attribute :parent_id in Hologram.PolicyTest.InlinePolicyFixture6 has type :uuid"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture6])
      end
    end
  end
end
