defmodule Hologram.Sync.WireDataTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.WireData

  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  @created_at ~U[2026-08-16 15:18:13.022508Z]
  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"
  @updated_at ~U[2026-08-16 16:20:00.000000Z]

  defp module_2(overrides \\ %{}) do
    defaults = %{
      a: true,
      b: 7,
      c: "text",
      created_at: @created_at,
      id: @entity_id,
      updated_at: @updated_at
    }

    struct(Module2, Map.merge(defaults, overrides))
  end

  describe "patch/2" do
    test "writes the changed attributes the way the row's are written" do
      assert patch(Module4, %{b: @created_at, c: :y}) == %{
               b: "2026-08-16T15:18:13.022508Z",
               c: "y"
             }
    end

    # Every update moves the stamp, so a patch carrying a struct value is the common case rather
    # than an edge one.
    test "writes the stamp every patch carries" do
      assert patch(Module2, %{c: "moved", updated_at: @updated_at}) == %{
               c: "moved",
               updated_at: "2026-08-16T16:20:00.000000Z"
             }
    end

    test "writes a reference field as the id it holds" do
      assert patch(Module3, %{b_id: @target_id}) == %{b_id: @target_id}
    end

    test "leaves out a value the client may not have" do
      changes = %{email: "user@test.com", password_hash: %ServerOnly{attribute: :password_hash}}

      assert patch(Module14, changes) == %{email: "user@test.com"}
    end

    test "leaves out a server-only attribute whose real value the changes are holding" do
      changes = %{email: "user@test.com", password_hash: "hashed_secret_v3"}

      assert patch(Module14, changes) == %{email: "user@test.com"}
    end

    test "writes nothing for changes holding nothing" do
      assert patch(Module2, %{}) == %{}
    end
  end

  describe "row/1" do
    test "writes every attribute the row holds, its system ones included" do
      assert row(module_2()) == %{
               a: true,
               b: 7,
               c: "text",
               created_at: "2026-08-16T15:18:13.022508Z",
               id: @entity_id,
               updated_at: "2026-08-16T16:20:00.000000Z"
             }
    end

    test "writes a date, a datetime and an enum the way the database codec writes them" do
      entity =
        struct(Module4, %{
          a: ~D[2026-08-16],
          b: @created_at,
          c: :y,
          d: 1.5,
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      wire = row(entity)

      assert wire.a == "2026-08-16"
      assert wire.b == "2026-08-16T15:18:13.022508Z"
      assert wire.c == "y"
      assert wire.d == 1.5
    end

    test "writes an unset attribute as null rather than leaving it out" do
      wire = row(module_2(%{b: nil}))

      assert Map.fetch(wire, :b) == {:ok, nil}
    end

    test "leaves out a value the client may not have" do
      entity =
        struct(Module14, %{
          created_at: @created_at,
          email: "user@test.com",
          id: @entity_id,
          password_hash: %ServerOnly{attribute: :password_hash},
          updated_at: @updated_at
        })

      wire = row(entity)

      assert wire.email == "user@test.com"
      refute Map.has_key?(wire, :password_hash)
    end

    # What the MODEL declares decides this, never what the row happens to hold: a row read through
    # the trusted tier carries the real value, and one just written carries what was written.
    test "leaves out a server-only attribute whose real value the row is holding" do
      entity =
        struct(Module14, %{
          created_at: @created_at,
          email: "user@test.com",
          id: @entity_id,
          password_hash: "hashed_secret_v3",
          updated_at: @updated_at
        })

      wire = row(entity)

      assert wire.email == "user@test.com"
      refute Map.has_key?(wire, :password_hash)
    end

    test "leaves out a relationship the query did not ask for" do
      entity =
        struct(Module3, %{created_at: @created_at, id: @entity_id, updated_at: @updated_at})

      wire = row(entity)

      refute Map.has_key?(wire, :a)
      refute Map.has_key?(wire, :b)
      refute Map.has_key?(wire, :c)
    end

    # The three absences cannot be confused, which is what lets a reader take absence as an answer:
    # an attribute is always there, a server-only one never is, a relationship exactly when asked.
    test "keeps the reference field of a relationship it left out" do
      entity =
        struct(Module3, %{
          b: %NotIncluded{relationship: :b},
          b_id: @target_id,
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      wire = row(entity)

      assert wire.b_id == @target_id
      refute Map.has_key?(wire, :b)
    end

    test "writes an included to-one relationship as the row it holds" do
      entity =
        struct(Module3, %{
          b: module_2(),
          b_id: @entity_id,
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      assert row(entity).b.c == "text"
    end

    test "writes an included to-one relationship holding nothing as null" do
      entity =
        struct(Module3, %{
          b: nil,
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      wire = row(entity)

      assert Map.fetch(wire, :b) == {:ok, nil}
    end

    test "writes an included to-many relationship as the rows it holds" do
      entity =
        struct(Module3, %{
          a: [module_2(), module_2(%{c: "second"})],
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      assert [first, second] = row(entity).a
      assert second.c == "second"

      # The whole row, not just its shape: a value left as a struct inside a to-many would still
      # answer to `.c` while travelling as something no client can read.
      assert first == %{
               a: true,
               b: 7,
               c: "text",
               created_at: "2026-08-16T15:18:13.022508Z",
               id: @entity_id,
               updated_at: "2026-08-16T16:20:00.000000Z"
             }
    end

    test "hides a server-only value however deep the row sits" do
      user =
        struct(Module14, %{
          created_at: @created_at,
          email: "nested@test.com",
          id: @entity_id,
          password_hash: %ServerOnly{attribute: :password_hash},
          updated_at: @updated_at
        })

      entity =
        struct(Module3, %{
          b: user,
          created_at: @created_at,
          id: @entity_id,
          updated_at: @updated_at
        })

      nested = row(entity).b

      assert nested.email == "nested@test.com"
      refute Map.has_key?(nested, :password_hash)
    end
  end
end
