defmodule Hologram.EntityTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity

  alias Hologram.Component.Action
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module11
  alias Hologram.Test.Fixtures.Entity.Module12
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1

  describe "__attributes__/0" do
    test "returns empty list for entity type with no attribute declarations" do
      assert Module1.__attributes__() == []
    end

    test "returns attribute definitions sorted by name regardless of declaration order" do
      assert Module2.__attributes__() == [
               {:a, :boolean, [default: false]},
               {:b, :integer, [optional: true]},
               {:c, :string, []}
             ]
    end
  end

  test "__is_hologram_entity__/0" do
    assert Module1.__is_hologram_entity__()
  end

  describe "__is_hologram_user_entity__/0" do
    test "is defined by the user option" do
      assert Module14.__is_hologram_user_entity__()
    end

    test "is not defined without the user option" do
      Code.ensure_loaded!(Module1)

      refute function_exported?(Module1, :__is_hologram_user_entity__, 0)
    end
  end

  describe "__policies__/0" do
    test "returns empty list for entity type with no policy declarations" do
      assert Module1.__policies__() == []
    end

    test "returns policy definitions in declaration order, splitting grant references off the predicates" do
      assert Module13.__policies__() == [
               {:read, nil, nil, [public: true]},
               {:read, [:editor, :owner], nil, []},
               {:publish, nil, :parent, []},
               {:triage, nil, nil, [priority: {:>=, 3}]},
               {:unlink, nil, nil, [parent_id: nil]}
             ]
    end
  end

  describe "__relationships__/0" do
    test "returns empty list for entity type with no relationship declarations" do
      assert Module1.__relationships__() == []
    end

    test "returns relationship definitions sorted by name regardless of declaration order" do
      assert Module3.__relationships__() == [
               {:a, [Module2], []},
               {:b, Module2, [optional: true]},
               {:c, Module1, []}
             ]
    end
  end

  describe "__roles__/0" do
    test "returns empty list for entity type with no role declarations" do
      assert Module1.__roles__() == []
    end

    test "returns role definitions sorted by name regardless of declaration order" do
      assert Module11.__roles__() == [{:editor, []}, {:owner, []}]
    end
  end

  describe "__struct__/0" do
    test "defines only the metadata and system attribute fields for entity type with no declarations" do
      field_names =
        %Module1{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:__meta__, :created_at, :id, :updated_at]
    end

    test "includes declared attribute fields" do
      field_names =
        %Module2{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:__meta__, :a, :b, :c, :created_at, :id, :updated_at]
    end

    test "defaults relationship embed and to-many fields to the NotIncluded sentinel" do
      entity = %Module3{}

      assert entity.a == %NotIncluded{relationship: :a}
      assert entity.b == %NotIncluded{relationship: :b}
      assert entity.c == %NotIncluded{relationship: :c}
      assert entity.b_id == nil
      assert entity.c_id == nil
    end

    test "splits relationships into reference and embed fields" do
      field_names =
        %Module3{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:__meta__, :a, :b, :b_id, :c, :c_id, :created_at, :id, :updated_at]
    end
  end

  describe "__system_attributes__/0" do
    test "returns system attribute definitions sorted by name on every entity type" do
      expected = [
        {:created_at, :datetime, []},
        {:id, :uuid, []},
        {:updated_at, :datetime, []}
      ]

      assert Module1.__system_attributes__() == expected
      assert Module2.__system_attributes__() == expected
    end
  end

  describe "allow/2" do
    test "replaces a user_id() call with the actor sentinel" do
      defmodule InlineEntityFixture1 do
        use Hologram.Entity

        allow :read, id: user_id()
      end

      assert InlineEntityFixture1.__policies__() == [{:read, nil, nil, [id: {:actor}]}]
    end

    test "replaces a user_id() call inside an operator tuple" do
      defmodule InlineEntityFixture2 do
        use Hologram.Entity

        allow :update, id: {:!=, user_id()}
      end

      assert InlineEntityFixture2.__policies__() == [{:update, nil, nil, [id: {:!=, {:actor}}]}]
    end

    test "rejects paren-less user_id" do
      expected_msg =
        "paren-less user_id in a policy in Hologram.EntityTest.InlineEntityFixture3 - did you mean user_id()?"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture3 do
          use Hologram.Entity

          allow :read, id: user_id
        end
      end
    end
  end

  describe "attribute/3" do
    test "accepts all valid attribute types" do
      assert Module4.__attributes__() == [
               {:a, :date, []},
               {:b, :datetime, []},
               {:c, :enum, [values: [:x, :y], default: :x]},
               {:d, :float, []}
             ]
    end
  end

  describe "expand_role/2" do
    test "returns the role name alone when no other role extends it" do
      assert expand_role(Module12, :admin) == [:admin]
    end

    test "returns the roles extending the given one through any number of hops" do
      assert expand_role(Module12, :viewer) == [:admin, :editor, :owner, :viewer]
    end

    test "returns the roles listing the given one among several extended roles" do
      assert expand_role(Module12, :owner) == [:admin, :owner]
    end

    test "returns the role name alone for entity type with no role declarations" do
      assert expand_role(Module1, :owner) == [:owner]
    end
  end

  # IMPORTANT!
  # Each test in this describe block has a related JavaScript test in test/javascript/utils_test.mjs (describe "uuidv7()")
  # Always update both together.
  describe "generate_id/0" do
    test "returns a version 7 UUID string" do
      assert generate_id() =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "returns a different id on each call" do
      assert generate_id() != generate_id()
    end

    test "embeds the number of milliseconds since the Unix epoch in the leading bits" do
      unix_ms_before = System.system_time(:millisecond)
      id = generate_id()
      unix_ms_after = System.system_time(:millisecond)

      embedded_unix_ms =
        id
        |> String.replace("-", "")
        |> String.slice(0, 12)
        |> String.to_integer(16)

      assert embedded_unix_ms >= unix_ms_before
      assert embedded_unix_ms <= unix_ms_after
    end
  end

  describe "new/2" do
    test "returns a struct of the given entity type with a generated id and nil system timestamps" do
      entity = new(Module1)

      assert is_struct(entity, Module1)

      assert entity.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      assert entity.created_at == nil
      assert entity.updated_at == nil
    end

    test "applies declared defaults to absent attributes" do
      entity = new(Module2)

      assert entity.a == false
      assert entity.b == nil
      assert entity.c == nil
    end

    test "keeps given attribute values over declared defaults" do
      assert new(Module2, %{a: true}).a == true
    end

    test "accepts values as a map" do
      assert new(Module2, %{c: "text_1"}).c == "text_1"
    end

    test "accepts values as a keyword list" do
      assert new(Module2, c: "text_2").c == "text_2"
    end

    test "keeps a given id" do
      assert new(Module2, %{id: "id_1"}).id == "id_1"
    end

    test "sets given to-one relationship references" do
      assert new(Module3, %{c_id: "id_2"}).c_id == "id_2"
    end

    test "builds a job queued, with nothing recorded of a run" do
      job = new(JobModule1)

      assert job.status == :queued
      assert job.actor_id == nil
      assert job.error == nil
    end

    test "raises on a role grant" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        new(Hologram.Auth.RoleGrant)
      end
    end

    test "raises on an assigned relationship value" do
      expected_msg =
        "relationship :c of Hologram.Test.Fixtures.Entity.Module3 cannot be assigned at construction - set a to-one reference via the :c_id field, to-many edges via add_relationship"

      assert_error ArgumentError, expected_msg, fn ->
        new(Module3, %{c: "id_2"})
      end
    end

    test "raises on an assigned job status" do
      expected_msg =
        ":status of Hologram.Test.Fixtures.Job.Module1 is set by the framework - a job is enqueued as queued, and the worker records the rest"

      assert_error ArgumentError, expected_msg, fn ->
        new(JobModule1, %{status: :done})
      end
    end

    test "raises on an assigned job actor" do
      expected_msg =
        ":actor_id of Hologram.Test.Fixtures.Job.Module1 is set by the framework - a job is enqueued as queued, and the worker records the rest"

      assert_error ArgumentError, expected_msg, fn ->
        new(JobModule1, %{actor_id: "018f4c11-1111-7111-8111-111111111111"})
      end
    end
  end

  describe "role/2" do
    test "unifies an identical re-declaration" do
      defmodule InlineRoleFixture1 do
        use Hologram.Entity

        role :owner, creator: true
        role :owner, creator: true
      end

      assert InlineRoleFixture1.__roles__() == [{:owner, [creator: true]}]
    end

    test "rejects a re-declaration with different options" do
      expected_msg =
        "conflicting declarations for role :owner in Hologram.EntityTest.InlineRoleFixture2: [] and [creator: true] - repeated role declarations must be identical"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineRoleFixture2 do
          use Hologram.Entity

          role :owner
          role :owner, creator: true
        end
      end
    end
  end

  describe "server_only_attribute_names/1" do
    test "returns the server-only attribute names sorted" do
      assert server_only_attribute_names(Module15) == [:secret_note, :token]
    end

    test "returns empty list for an entity type without server-only attributes" do
      assert server_only_attribute_names(Module2) == []
    end
  end

  describe "strip_server_only/1" do
    test "replaces every server-only value with the sentinel, leaving the rest untouched" do
      entity = new(Module15, label: "Report", secret_note: "internal", token: "tok_9xK2")

      stripped = strip_server_only(entity)

      assert stripped.secret_note == %ServerOnly{attribute: :secret_note}
      assert stripped.token == %ServerOnly{attribute: :token}
      assert stripped.label == "Report"
      assert stripped.id == entity.id
    end

    test "returns an entity type without server-only attributes unchanged" do
      entity = new(Module2, a: true, b: 5, c: "abc")

      assert strip_server_only(entity) == entity
    end
  end

  describe "strip_server_only_deep/1" do
    test "strips entity structs nested in lists" do
      entity = new(Module15, label: "Report", token: "tok_A1")

      assert strip_server_only_deep([[entity], []]) == [[strip_server_only(entity)], []]
    end

    test "strips an entity struct held in a relationship embed field" do
      child = new(Module15, token: "tok_B2")
      parent = %Module13{parent: child}

      assert strip_server_only_deep(parent) == %Module13{parent: strip_server_only(child)}
    end

    test "strips an entity struct nested in a map inside a non-entity struct" do
      entity = new(Module15, token: "tok_C3")
      action = %Action{name: :save, params: %{row: entity}}

      expected_params = %{row: strip_server_only(entity)}

      assert strip_server_only_deep(action) == %Action{name: :save, params: expected_params}
    end

    test "strips an entity struct used as a map key" do
      entity = new(Module15, label: "Report", token: "tok_D4")

      assert strip_server_only_deep(%{entity => "held"}) == %{strip_server_only(entity) => "held"}
    end

    test "returns a value struct unchanged" do
      datetime = ~U[2026-01-01 00:00:00Z]

      assert strip_server_only_deep(datetime) == datetime
    end

    test "returns a term holding no entity structs unchanged" do
      term = %{a: [1, {:b, "c"}], d: nil}

      assert strip_server_only_deep(term) == term
    end
  end

  describe "validate/1" do
    test "returns :ok for a valid entity struct" do
      entity = new(Module10, count: 5)

      assert validate(entity) == :ok
    end

    test "reports violations grouped by field name" do
      entity = new(Module2, b: "nope")

      assert validate(entity) == {:error, %{b: [{:type, :integer}], c: [:required]}}
    end

    test "accumulates multiple reasons per field" do
      entity = new(Module10, count: 5, handle: "A?")

      assert {:error, %{handle: [format_reason, {:min_length, 3}]}} = validate(entity)

      assert {:format, format} = format_reason
      assert Regex.source(format) == "^[a-z_]+$"
    end

    test "reports missing required reference" do
      entity = new(Module3)

      assert validate(entity) == {:error, %{c_id: [:required]}}
    end
  end

  describe "validate/2" do
    test "returns :ok for valid changes given as a keyword list" do
      assert validate(Module10, count: 5) == :ok
    end

    test "does not require absent fields" do
      assert validate(Module2, %{}) == :ok
    end

    test "reports violations grouped by field name" do
      assert validate(Module10, %{count: 0, username: 5}) ==
               {:error, %{count: [{:min, 1}], username: [{:type, :string}]}}
    end

    test "reports nil for non-optional attribute as required" do
      assert validate(Module2, %{c: nil}) == {:error, %{c: [:required]}}
    end
  end
end
