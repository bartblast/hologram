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
  alias Hologram.Test.Fixtures.Entity.Module20
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5
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

  describe "__policy_sources__/0" do
    test "returns empty list for entity type with no policy declarations" do
      assert Module1.__policy_sources__() == []
    end

    test "lines up with __policies__/0 across taken and local lines" do
      defmodule PolicySourcesEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1

        allow :delete, to: :viewer
      end

      assert PolicySourcesEntityFixture.__policies__() == [
               {:read, :viewer, nil, []},
               {:delete, :viewer, nil, []}
             ]

      assert PolicySourcesEntityFixture.__policy_sources__() == [
               Hologram.Test.Fixtures.Policy.Shared.Module1,
               PolicySourcesEntityFixture
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

  describe "__role_declarations__/0" do
    test "returns empty list for entity type with no role declarations" do
      assert Module1.__role_declarations__() == []
    end

    test "keeps every declaration of a unioned role beside the module it was written in" do
      defmodule RoleDeclarationsEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1

        role :viewer, granted_to: :creator
      end

      assert RoleDeclarationsEntityFixture.__roles__() == [{:viewer, [granted_to: :creator]}]

      assert RoleDeclarationsEntityFixture.__role_declarations__() == [
               {:viewer, [], Hologram.Test.Fixtures.Policy.Shared.Module1},
               {:viewer, [granted_to: :creator], RoleDeclarationsEntityFixture}
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

    test "carries the declared attribute defaults" do
      assert %Module2{}.a == false
      assert %Module4{}.c == :x
      assert %Module20{}.count == 0
    end

    test "leaves an attribute declaring no default nil" do
      assert %Module2{}.b == nil
      assert %Module2{}.c == nil
    end

    test "carries a job's queued status" do
      assert %JobModule1{}.status == :queued
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

  describe "new/1" do
    test "builds the struct the engine builds for the type" do
      entity = Module2.new(c: "text_4")

      assert is_struct(entity, Module2)

      assert entity.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      assert entity.a == false
      assert entity.c == "text_4"
      assert entity.created_at == nil
    end

    test "accepts values as a map" do
      assert Module2.new(%{c: "text_5"}).c == "text_5"
    end

    test "takes no values" do
      entity = Module1.new()

      assert is_struct(entity, Module1)

      assert entity.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "builds a job through its own type" do
      assert JobModule1.new().status == :queued
    end

    # An override reaches the generated constructor through super, which is resolved by Elixir
    # before the compiler sees the module - so it transpiles to an ordinary private call and the
    # override applies in the browser as well as on the server.
    test "lets an entity type override the generated constructor" do
      defmodule InlineConstructorFixture1 do
        use Hologram.Entity

        attribute :a, :string

        @spec new(keyword) :: struct
        def new(values), do: super(Keyword.put(values, :a, "overridden"))
      end

      assert InlineConstructorFixture1.new(a: "given").a == "overridden"
      assert InlineConstructorFixture1.new().a == "overridden"
    end

    test "refuses what the engine refuses, in its words" do
      expected_msg =
        "relationship :c of Hologram.Test.Fixtures.Entity.Module3 cannot be assigned at construction - set a to-one reference via the :c_id field, to-many edges via add_relationship"

      assert_error ArgumentError, expected_msg, fn ->
        Module3.new(c: "id_2")
      end
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

  # The taken policy is the shared fixture rather than an inline module: this file imports
  # Hologram.Entity, and a nested defmodule with use Hologram.Policy inherits that import,
  # which collides on role/1 and allow/1.
  describe "policy/1" do
    test "takes the roles and rules of the given policy module" do
      defmodule TakingEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1
      end

      assert TakingEntityFixture.__roles__() == [{:viewer, []}]
      assert TakingEntityFixture.__policies__() == [{:read, :viewer, nil, []}]
    end

    test "keeps the entity's own declarations beside the taken ones, taken first" do
      defmodule CoexistEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1

        role :owner

        allow :delete, to: :owner
      end

      assert CoexistEntityFixture.__roles__() == [{:owner, []}, {:viewer, []}]

      assert CoexistEntityFixture.__policies__() == [
               {:read, :viewer, nil, []},
               {:delete, :owner, nil, []}
             ]
    end

    test "contributes roles that a locally declared extends option can name" do
      defmodule ExtendsEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1

        role :owner, extends: :viewer
      end

      assert ExtendsEntityFixture.__roles__() == [{:owner, [extends: :viewer]}, {:viewer, []}]
    end
  end

  describe "role/2" do
    test "unifies an identical re-declaration" do
      defmodule InlineRoleFixture1 do
        use Hologram.Entity

        role :owner, granted_to: :creator
        role :owner, granted_to: :creator
      end

      assert InlineRoleFixture1.__roles__() == [{:owner, [granted_to: :creator]}]
    end

    test "unifies a re-declaration written with the options in a different order" do
      defmodule InlineRoleFixture2 do
        use Hologram.Entity

        role :editor
        role :owner, extends: :editor, granted_to: :creator
        role :owner, granted_to: :creator, extends: :editor
      end

      assert InlineRoleFixture2.__roles__() == [
               {:editor, []},
               {:owner, [extends: [:editor], granted_to: :creator]}
             ]
    end

    test "unions the extends targets of several declarations" do
      defmodule InlineRoleFixture3 do
        use Hologram.Entity

        role :editor
        role :viewer
        role :owner, extends: :viewer
        role :owner, extends: :editor
      end

      assert InlineRoleFixture3.__roles__() == [
               {:editor, []},
               {:owner, [extends: [:editor, :viewer]]},
               {:viewer, []}
             ]
    end

    test "keeps granted_to declared by one declaration and unmentioned by the other" do
      defmodule InlineRoleFixture4 do
        use Hologram.Entity

        role :owner, granted_to: :creator
        role :owner, extends: :editor
        role :editor
      end

      assert InlineRoleFixture4.__roles__() == [
               {:editor, []},
               {:owner, [extends: [:editor], granted_to: :creator]}
             ]
    end

    test "lets the last declaration mentioning granted_to switch the grant off" do
      defmodule InlineRoleFixture5 do
        use Hologram.Entity

        role :owner, granted_to: :creator
        role :owner, granted_to: nil
      end

      assert InlineRoleFixture5.__roles__() == [{:owner, []}]
    end

    test "lets the last declaration mentioning granted_to switch the grant on" do
      defmodule InlineRoleFixture6 do
        use Hologram.Entity

        role :owner, granted_to: nil
        role :owner, granted_to: :creator
      end

      assert InlineRoleFixture6.__roles__() == [{:owner, [granted_to: :creator]}]
    end

    test "accepts a lone granted_to: nil declaration" do
      defmodule InlineRoleFixture7 do
        use Hologram.Entity

        role :owner, granted_to: nil
      end

      assert InlineRoleFixture7.__roles__() == [{:owner, []}]
    end

    test "merges a role reached through a policy with a local declaration of the same name" do
      defmodule PolicyRoleEntityFixture do
        use Hologram.Entity

        policy Hologram.Test.Fixtures.Policy.Shared.Module1

        role :viewer, granted_to: :creator
      end

      assert PolicyRoleEntityFixture.__roles__() == [{:viewer, [granted_to: :creator]}]
    end

    test "validates a re-declaration of a role already declared" do
      expected_msg =
        "invalid granted_to option false for role :owner in Hologram.EntityTest.InlineRoleFixture8 - the granted_to option must be :creator or nil"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineRoleFixture8 do
          use Hologram.Entity

          role :owner, granted_to: :creator
          role :owner, granted_to: false
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

  describe "t/0" do
    test "types a declared enum attribute as its declared values" do
      assert struct_field_types(Module4) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               a: "Date.t() | nil",
               b: "DateTime.t() | nil",
               c: ":x | :y | nil",
               created_at: "DateTime.t() | nil",
               d: "float() | nil",
               id: "String.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
    end

    # The self-reference reads back as a bare t() rather than as the module's own name - that is
    # how Erlang stores a type naming the module it is defined in, not something to correct.
    test "types a self-referencing relationship as the entity type's own type" do
      assert struct_field_types(Module5) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               a:
                 "Hologram.Test.Fixtures.Entity.Module3.t() | Hologram.Entity.NotIncluded.t() | nil",
               a_id: "String.t() | nil",
               b: "t() | Hologram.Entity.NotIncluded.t() | nil",
               b_id: "String.t() | nil",
               created_at: "DateTime.t() | nil",
               id: "String.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
    end

    test "types a server-only attribute as admitting its sentinel" do
      assert struct_field_types(Module15) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               created_at: "DateTime.t() | nil",
               id: "String.t() | nil",
               label: "String.t() | nil",
               secret_note: "String.t() | Hologram.Entity.ServerOnly.t() | nil",
               token: "String.t() | Hologram.Entity.ServerOnly.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
    end

    test "types declared attributes from the types their declarations name" do
      assert struct_field_types(Module2) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               a: "boolean() | nil",
               b: "integer() | nil",
               c: "String.t() | nil",
               created_at: "DateTime.t() | nil",
               id: "String.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
    end

    test "types relationship fields from the entity types they target" do
      assert struct_field_types(Module3) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               a: "[Hologram.Test.Fixtures.Entity.Module2.t()] | Hologram.Entity.NotIncluded.t()",
               b:
                 "Hologram.Test.Fixtures.Entity.Module2.t() | Hologram.Entity.NotIncluded.t() | nil",
               b_id: "String.t() | nil",
               c:
                 "Hologram.Test.Fixtures.Entity.Module1.t() | Hologram.Entity.NotIncluded.t() | nil",
               c_id: "String.t() | nil",
               created_at: "DateTime.t() | nil",
               id: "String.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
    end

    test "types the metadata and system attribute fields on an entity type declaring nothing" do
      assert struct_field_types(Module1) == %{
               __meta__: "Hologram.Entity.Metadata.t()",
               created_at: "DateTime.t() | nil",
               id: "String.t() | nil",
               updated_at: "DateTime.t() | nil"
             }
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
