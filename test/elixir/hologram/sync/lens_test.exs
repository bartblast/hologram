defmodule Hologram.Sync.LensTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Lens

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Lens
  alias Hologram.Test.Fixtures.Entity.Module21
  alias Hologram.Test.Fixtures.Entity.Module30
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module40

  # Op maps as `use Hologram.Migration` records them. The lens reads only the ops, so the modules
  # they name need not exist.
  @trip MyApp.Trip
  @journey MyApp.Journey
  @stop MyApp.Stop
  @admin MyApp.Roles.Admin
  @staff MyApp.Roles.Staff

  # The model term at the tab's point. Only server-only attributes and the user entity type are
  # read from it.
  @model %{entities: %{}, roles: %{}, user_entity: nil}

  defp trip_entry(budget_opts) do
    %{
      attributes: [{:budget, :integer, budget_opts}],
      relationships: [],
      roles: [],
      uniques: []
    }
  end

  defp lens!(ops, model \\ @model) do
    {:ok, lens} = build(model, ops)

    lens
  end

  describe "build/2" do
    test "no ops give a lens that changes nothing" do
      lens = lens!([])

      assert lens == %Lens{}
      assert old_type(lens, @trip) == @trip
      assert old_attribute(lens, @trip, :destination) == :destination
      assert old_relationship(lens, @trip, :stops) == :stops
      assert old_enum_value(lens, @trip, :status, :draft) == :draft
      assert old_role(lens, @trip, :owner) == :owner
      assert old_global_role(lens, @admin) == @admin
    end

    test "a created entity type is new, and so is everything on it" do
      lens =
        lens!([
          %{op: :create_entity, entity: @stop},
          %{op: :add_attribute, entity: @stop, name: :city, type: :string, opts: []},
          %{op: :add_role, entity: @stop, name: :guide, opts: []}
        ])

      assert old_type(lens, @stop) == new_since()
      assert old_attribute(lens, @stop, :city) == new_since()
      assert old_relationship(lens, @stop, :trip) == new_since()
      assert old_enum_value(lens, @stop, :kind, :bus) == new_since()
      assert old_role(lens, @stop, :guide) == new_since()
      assert old_type(lens, @trip) == @trip
    end

    test "a renamed entity type keeps its old name and what was said of its members" do
      lens =
        lens!([
          %{op: :rename_attribute, entity: @trip, from: :destination, to: :place},
          %{op: :rename_entity, from: @trip, to: @journey}
        ])

      assert old_type(lens, @journey) == @trip
      assert old_attribute(lens, @journey, :place) == :destination
      assert old_attribute(lens, @journey, :notes) == :notes
    end

    test "a type renamed twice keeps its first name" do
      lens =
        lens!([
          %{op: :rename_entity, from: @trip, to: @journey},
          %{op: :rename_entity, from: @journey, to: @stop}
        ])

      assert old_type(lens, @stop) == @trip
    end

    test "a type created and then renamed stays new" do
      lens =
        lens!([
          %{op: :create_entity, entity: @stop},
          %{op: :rename_entity, from: @stop, to: @journey}
        ])

      assert old_type(lens, @journey) == new_since()
      assert old_attribute(lens, @journey, :city) == new_since()
    end

    test "an added attribute is new" do
      lens = lens!([%{op: :add_attribute, entity: @trip, name: :notes, type: :string, opts: []}])

      assert old_attribute(lens, @trip, :notes) == new_since()
      assert old_attribute(lens, @trip, :destination) == :destination
    end

    test "a renamed attribute keeps its old name" do
      lens = lens!([%{op: :rename_attribute, entity: @trip, from: :destination, to: :place}])

      assert old_attribute(lens, @trip, :place) == :destination
    end

    test "an attribute renamed twice keeps its first name" do
      lens =
        lens!([
          %{op: :rename_attribute, entity: @trip, from: :destination, to: :place},
          %{op: :rename_attribute, entity: @trip, from: :place, to: :where}
        ])

      assert old_attribute(lens, @trip, :where) == :destination
    end

    test "an attribute renamed and back is itself" do
      lens =
        lens!([
          %{op: :rename_attribute, entity: @trip, from: :destination, to: :place},
          %{op: :rename_attribute, entity: @trip, from: :place, to: :destination}
        ])

      assert old_attribute(lens, @trip, :destination) == :destination
    end

    test "a name given to a new attribute after a rename took it away is new" do
      lens =
        lens!([
          %{op: :rename_attribute, entity: @trip, from: :destination, to: :place},
          %{op: :add_attribute, entity: @trip, name: :destination, type: :string, opts: []}
        ])

      assert old_attribute(lens, @trip, :place) == :destination
      assert old_attribute(lens, @trip, :destination) == new_since()
    end

    test "an added attribute renamed later stays new" do
      lens =
        lens!([
          %{op: :add_attribute, entity: @trip, name: :notes, type: :string, opts: []},
          %{op: :rename_attribute, entity: @trip, from: :notes, to: :remarks}
        ])

      assert old_attribute(lens, @trip, :remarks) == new_since()
    end

    test "an added relationship is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_relationship, entity: @trip, name: :stops, type: [@stop], opts: []},
          %{op: :rename_relationship, entity: @trip, from: :owner, to: :organizer}
        ])

      assert old_relationship(lens, @trip, :stops) == new_since()
      assert old_relationship(lens, @trip, :organizer) == :owner
      assert old_relationship(lens, @trip, :owner) == :owner
    end

    test "an added enum value is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: @trip, attribute: :status, value: :cancelled, opts: []},
          %{op: :rename_enum_value, entity: @trip, attribute: :status, from: :done, to: :finished}
        ])

      assert old_enum_value(lens, @trip, :status, :cancelled) == new_since()
      assert old_enum_value(lens, @trip, :status, :finished) == :done
      assert old_enum_value(lens, @trip, :status, :draft) == :draft
    end

    test "an enum value named new that the walk never touched is itself" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: @trip, attribute: :status, value: :closed, opts: []}
        ])

      assert old_enum_value(lens, @trip, :status, :new) == :new
      assert old_enum_value(lens, @trip, :status, :closed) == new_since()
    end

    test "an enum value renamed and back is itself" do
      lens =
        lens!([
          %{
            op: :rename_enum_value,
            entity: @trip,
            attribute: :status,
            from: :done,
            to: :finished
          },
          %{op: :rename_enum_value, entity: @trip, attribute: :status, from: :finished, to: :done}
        ])

      assert old_enum_value(lens, @trip, :status, :done) == :done
    end

    test "an enum attribute's values follow its rename" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: @trip, attribute: :status, value: :cancelled, opts: []},
          %{op: :rename_attribute, entity: @trip, from: :status, to: :state},
          %{op: :rename_enum_value, entity: @trip, attribute: :state, from: :done, to: :finished}
        ])

      assert old_enum_value(lens, @trip, :state, :cancelled) == new_since()
      assert old_enum_value(lens, @trip, :state, :finished) == :done
      assert old_enum_value(lens, @trip, :status, :cancelled) == :cancelled
    end

    test "any value of an added enum attribute is new" do
      lens =
        lens!([
          %{op: :add_attribute, entity: @trip, name: :kind, type: :enum, opts: [values: [:a]]}
        ])

      assert old_enum_value(lens, @trip, :kind, :a) == new_since()
    end

    test "an added entity role is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_role, entity: @trip, name: :guide, opts: []},
          %{op: :rename_role, entity: @trip, from: :editor, to: :maintainer}
        ])

      assert old_role(lens, @trip, :guide) == new_since()
      assert old_role(lens, @trip, :maintainer) == :editor
      assert old_role(lens, @trip, :owner) == :owner
      assert old_role(lens, @stop, :maintainer) == :maintainer
    end

    test "an added global role is new, a renamed one keeps its old module" do
      auditor = MyApp.Roles.Auditor

      lens =
        lens!([
          %{op: :add_role, role: auditor, opts: []},
          %{op: :rename_role, from: @admin, to: @staff}
        ])

      assert old_global_role(lens, auditor) == new_since()
      assert old_global_role(lens, @staff) == @admin
      assert old_global_role(lens, @admin) == @admin
    end

    test "changes that keep every row's shape change nothing" do
      ops = [
        %{op: :add_unique, entity: @trip, fields: [:slug]},
        %{op: :delete_unique, entity: @trip, fields: [:code]},
        %{op: :reorder_enum_values, entity: @trip, attribute: :status, values: [:done, :draft]},
        %{op: :change_role, entity: @trip, name: :editor, changes: [extends: [:viewer]]},
        %{op: :change_role, entity: @trip, name: :owner, changes: [granted_to: :creator]},
        %{op: :change_role, role: @admin, changes: [extends: [@staff]]},
        %{op: :change_relationship, entity: @trip, name: :owner, changes: [optional: false]},
        %{op: :change_relationship, entity: @trip, name: :owner, changes: [unique: true]},
        %{op: :change_relationship, entity: @trip, name: :stops, changes: [sort: :position]},
        %{op: :change_relationship, entity: @trip, name: :owner, changes: [optional: nil]},
        %{op: :change_attribute, entity: @trip, name: :notes, changes: [optional: nil]},
        %{
          op: :change_attribute,
          entity: @trip,
          name: :title,
          changes: [
            default: "Untitled",
            format: ~r/\A\w+\z/,
            in: ["a", "b"],
            length: 3,
            max: 9,
            max_length: 80,
            min: 1,
            min_length: 2,
            optional: false,
            unique: true
          ]
        }
      ]

      assert build(@model, ops) == {:ok, %Lens{}}
    end

    test "an attribute the tab had as server-only is new once turned off, whatever else the change says" do
      model = %{@model | entities: %{@trip => trip_entry(server_only: true)}}

      for flag <- [false, nil] do
        lens =
          lens!(
            [
              %{
                op: :change_attribute,
                entity: @trip,
                name: :budget,
                changes: [default: 0, server_only: flag]
              }
            ],
            model
          )

        assert old_attribute(lens, @trip, :budget) == new_since()
      end
    end

    test "an attribute the tab had as server-only is new once turned off under another name" do
      model = %{@model | entities: %{@trip => trip_entry(server_only: true)}}

      lens =
        lens!(
          [
            %{op: :rename_entity, from: @trip, to: @journey},
            %{op: :rename_attribute, entity: @journey, from: :budget, to: :cost},
            %{op: :change_attribute, entity: @journey, name: :cost, changes: [server_only: false]}
          ],
          model
        )

      assert old_attribute(lens, @journey, :cost) == new_since()
    end

    test "an attribute the tab could read turned server-only off changes nothing" do
      model = %{@model | entities: %{@trip => trip_entry([])}}

      ops = [
        %{op: :change_attribute, entity: @trip, name: :budget, changes: [server_only: false]}
      ]

      assert build(model, ops) == {:ok, %Lens{}}
    end

    test "a user entity type renamed and designated under its new name stays served" do
      model = %{@model | user_entity: @trip}

      lens =
        lens!(
          [
            %{op: :rename_entity, from: @trip, to: @journey},
            %{op: :designate_user_entity, entity: @journey}
          ],
          model
        )

      assert old_type(lens, @journey) == @trip
    end

    test "a user entity type renamed twice and designated under its last name stays served" do
      lens =
        lens!(
          [
            %{op: :rename_entity, from: @trip, to: @journey},
            %{op: :rename_entity, from: @journey, to: @stop},
            %{op: :designate_user_entity, entity: @stop}
          ],
          %{@model | user_entity: @trip}
        )

      assert old_type(lens, @stop) == @trip
    end

    test "a user entity type the walk changes nothing of gives the lens that changes nothing" do
      assert build(%{@model | user_entity: @trip}, []) == {:ok, %Lens{}}
    end

    test "a designation that moves, arrives or leaves makes the chain unservable" do
      assert build(%{@model | user_entity: @trip}, [
               %{op: :designate_user_entity, entity: @stop}
             ]) == :unservable

      assert build(@model, [%{op: :designate_user_entity, entity: @trip}]) == :unservable

      assert build(%{@model | user_entity: @trip}, [
               %{op: :designate_user_entity, entity: nil}
             ]) == :unservable
    end

    test "an op no renaming can give back makes the chain unservable" do
      unservable = [
        %{op: :delete_attribute, entity: @trip, name: :notes},
        %{op: :delete_relationship, entity: @trip, name: :stops},
        %{op: :delete_entity, entity: @stop},
        %{op: :delete_enum_value, entity: @trip, attribute: :status, value: :done},
        %{op: :delete_role, entity: @trip, name: :editor},
        %{op: :delete_role, role: @admin},
        %{op: :delete_role_grants, line: 3},
        %{op: :resolve!, kind: :rename, payload: %{}, line: 3},
        %{op: :some_future_op}
      ]

      for op <- unservable do
        assert build(@model, [op]) == :unservable, inspect(op)
      end
    end

    test "a change no renaming can give back makes the chain unservable" do
      changes = [
        {:change_attribute, [type: :float]},
        {:change_attribute, [values: [:a, :b]]},
        {:change_attribute, [optional: true]},
        {:change_attribute, [server_only: true]},
        {:change_attribute, [default: 0, optional: true]},
        {:change_attribute, [server_only: false, type: :float]},
        {:change_attribute, [some_future_option: 1]},
        {:change_relationship, [type: @stop]},
        {:change_relationship, [optional: true]},
        {:change_relationship, [some_future_option: 1]}
      ]

      for {op, change} <- changes do
        assert build(@model, [%{op: op, entity: @trip, name: :x, changes: change}]) == :unservable,
               inspect({op, change})
      end

      assert build(@model, [%{op: :change_role, entity: @trip, name: :x, changes: [other: 1]}]) ==
               :unservable

      assert build(@model, [%{op: :change_role, role: @admin, changes: [other: 1]}]) ==
               :unservable
    end

    test "an unservable op anywhere in the chain makes it unservable" do
      ops = [
        %{op: :add_attribute, entity: @trip, name: :notes, type: :string, opts: []},
        %{op: :delete_attribute, entity: @trip, name: :legacy},
        %{op: :rename_entity, from: @trip, to: @journey}
      ]

      assert build(@model, ops) == :unservable
    end
  end

  # The fixtures the translation reads: Module39 has an enum `kind` (:guest, :staff), a to-one
  # `member` and a to-many `mentors`, both of Module34. Module30 has a to-many `follows` with its
  # inverse `followers`, and a to-one `parent` with its inverse `replies`.
  @entity_types [Module30, Module34, Module39, RoleGrant]

  @id_1 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e01"
  @id_2 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e02"

  defp resolved!(ops, model \\ @model) do
    ops
    |> lens!(model)
    |> resolve(@entity_types)
  end

  # Edges as `Hologram.Sync.Pot` hands them to `Hologram.Sync.Frame`: the relationship a string.
  defp edge_deltas(op, relationships) do
    edges =
      for relationship <- relationships do
        %{entity_id: @id_1, op: op, relationship: relationship, target_id: @id_2, type: Module30}
      end

    Frame.deltas(%{appeared: [], edges: edges, patched: [], unsynced: []}, nil)
  end

  defp deltas(lens, deltas) do
    {:sync_deltas, "cursor", translated, 7} = message(lens, {:sync_deltas, "cursor", deltas, 7})

    translated
  end

  defp label(module), do: Codec.encode_enum_value(module)

  describe "message/2" do
    test "a put takes the old keys and revisions, without what is new since" do
      lens =
        resolved!([
          %{op: :rename_attribute, entity: Module39, from: :points, to: :score},
          %{op: :add_relationship, entity: Module39, name: :mentors, type: [Module34], opts: []},
          %{op: :rename_relationship, entity: Module39, from: :buddy, to: :member}
        ])

      row = %Module39{
        __meta__: %Metadata{revisions: %{kind: 1, member_id: 2, score: 3}},
        id: @id_1,
        kind: :staff,
        member_id: @id_2,
        mentors: [%Module34{id: @id_2}],
        score: 5
      }

      [put] = deltas(lens, [Frame.put_entity(row, %{})])

      assert put.type == label(Module39)

      assert put.data == %{
               "$revisions": %{buddy_id: 2, kind: 1, points: 3},
               buddy_id: @id_2,
               created_at: nil,
               id: @id_1,
               kind: "staff",
               points: 5,
               server_created_at: nil,
               server_updated_at: nil,
               updated_at: nil
             }
    end

    test "a to-many renamed since goes under its old name, and its edges too, while its inverse keeps its own" do
      lens =
        resolved!([%{op: :rename_relationship, entity: Module30, from: :likes, to: :follows}])

      put = %{
        data: %{followers: [@id_2], follows: [@id_2], id: @id_1},
        id: @id_1,
        op: :put_entity,
        type: label(Module30)
      }

      assert deltas(lens, [put | edge_deltas(:add_relationship, ["follows", "followers"])]) == [
               %{put | data: %{followers: [@id_2], id: @id_1, likes: [@id_2]}}
               | edge_deltas(:add_relationship, ["likes", "followers"])
             ]
    end

    test "a to-many new since leaves out its set, its inverse's set and the edges of both" do
      lens =
        resolved!([
          %{op: :add_relationship, entity: Module30, name: :follows, type: [Module30], opts: []}
        ])

      put = %{
        data: %{body: "hi", followers: [@id_2], follows: [@id_2], id: @id_1},
        id: @id_1,
        op: :put_entity,
        type: label(Module30)
      }

      edges = edge_deltas(:del_relationship, ["follows", "followers"])

      assert deltas(lens, [put | edges]) == [%{put | data: %{body: "hi", id: @id_1}}]
    end

    test "a to-one renamed since takes its old reference field" do
      lens =
        resolved!([%{op: :rename_relationship, entity: Module30, from: :reply_to, to: :parent}])

      put = %{
        data: %{body: "hi", id: @id_1, parent_id: @id_2},
        id: @id_1,
        op: :put_entity,
        type: label(Module30)
      }

      assert deltas(lens, [put]) == [%{put | data: %{body: "hi", id: @id_1, reply_to_id: @id_2}}]
    end

    test "a to-one new since leaves out its reference field and its revision" do
      lens =
        resolved!([
          %{op: :add_relationship, entity: Module39, name: :member, type: Module34, opts: []}
        ])

      row = %Module39{
        __meta__: %Metadata{revisions: %{member_id: 2, score: 3}},
        id: @id_1,
        member_id: @id_2,
        score: 5
      }

      [put] = deltas(lens, [Frame.put_entity(row, %{})])

      refute Map.has_key?(put.data, :member_id)
      assert put.data[:"$revisions"] == %{score: 3}
      assert put.data.score == 5
    end

    test "a patch takes the old keys and revisions, a to-one's among them" do
      lens =
        resolved!([
          %{op: :rename_relationship, entity: Module39, from: :buddy, to: :member},
          %{op: :add_attribute, entity: Module39, name: :score, type: :integer, opts: []}
        ])

      row = %Module39{
        __meta__: %Metadata{revisions: %{member_id: 2, score: 3}},
        id: @id_1,
        member_id: @id_2,
        score: 5
      }

      news = %{
        appeared: [],
        edges: [],
        patched: [{row, %{member_id: @id_2, score: 5}, nil}],
        unsynced: []
      }

      assert [%{op: :patch_entity} = patch] = deltas(lens, Frame.deltas(news, nil))
      assert patch.data == %{"$revisions": %{buddy_id: 2}, buddy_id: @id_2}
    end

    test "an enum value takes its old label, and one of an attribute renamed since too" do
      lens =
        resolved!([
          %{
            op: :rename_enum_value,
            entity: Module39,
            attribute: :category,
            from: :worker,
            to: :staff
          },
          %{op: :rename_attribute, entity: Module39, from: :category, to: :kind}
        ])

      put = %{
        data: %{id: @id_1, kind: "staff"},
        id: @id_1,
        op: :put_entity,
        type: label(Module39)
      }

      guest = %{put | data: %{id: @id_1, kind: "guest"}}
      unset = %{put | data: %{id: @id_1, kind: nil}}

      assert deltas(lens, [put, guest, unset]) == [
               %{put | data: %{category: "worker", id: @id_1}},
               %{put | data: %{category: "guest", id: @id_1}},
               %{put | data: %{category: nil, id: @id_1}}
             ]
    end

    test "a row holding an enum value new since is dropped" do
      lens =
        resolved!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      put = %{
        data: %{id: @id_1, kind: "staff"},
        id: @id_1,
        op: :put_entity,
        type: label(Module39)
      }

      patch = %{put | op: :patch_entity}

      assert deltas(lens, [put, patch]) == []
    end

    test "a patch of only what is new since is dropped, unless it carries verdicts" do
      lens =
        resolved!([
          %{op: :add_attribute, entity: Module39, name: :score, type: :integer, opts: []}
        ])

      patch = %{
        data: %{"$revisions": %{score: 4}, score: 9},
        id: @id_1,
        op: :patch_entity,
        type: label(Module39)
      }

      with_verdicts = %{patch | data: Map.put(patch.data, :"$verdicts", %{"read:ab" => true})}
      with_kind = %{patch | data: %{"$revisions": %{kind: 5, score: 4}, kind: "guest", score: 9}}

      assert deltas(lens, [patch, with_verdicts, with_kind]) == [
               %{patch | data: %{"$revisions": %{}, "$verdicts": %{"read:ab" => true}}},
               %{patch | data: %{"$revisions": %{kind: 5}, kind: "guest"}}
             ]
    end

    test "drops, hashed drops and kept lists name the old type, and none of a type new since" do
      lens =
        resolved!([
          %{op: :rename_entity, from: MyApp.Member, to: Module34},
          %{op: :create_entity, entity: Module30}
        ])

      hashes = %{hashes: ["0123456789abcdef"], salt: "s"}

      deltas = [
        %{id: @id_1, op: :unsync_entity, type: label(Module34)},
        %{data: hashes, op: :unsync_hashed, type: label(Module34)},
        %{data: hashes, op: :keep_hashed, type: label(Module34)},
        %{id: @id_1, op: :unsync_entity, type: label(Module30)},
        %{data: hashes, op: :keep_hashed, type: label(Module30)}
      ]

      assert deltas(lens, deltas) == [
               %{id: @id_1, op: :unsync_entity, type: "MyApp.Member"},
               %{data: hashes, op: :unsync_hashed, type: "MyApp.Member"},
               %{data: hashes, op: :keep_hashed, type: "MyApp.Member"}
             ]
    end

    test "a delta of a type new since is dropped, listed or not" do
      lens =
        [%{op: :create_entity, entity: MyApp.Unlisted}]
        |> lens!()
        |> resolve(@entity_types)

      assert deltas(lens, [%{id: @id_1, op: :unsync_entity, type: "MyApp.Unlisted"}]) == []
    end

    test "a type the lens changes nothing of passes as it is" do
      lens =
        resolved!([
          %{op: :add_attribute, entity: Module39, name: :score, type: :integer, opts: []}
        ])

      put = %{
        data: %{id: @id_1, nickname: "x"},
        id: @id_1,
        op: :put_entity,
        type: label(Module34)
      }

      assert deltas(lens, [put]) == [put]
    end

    test "a grant takes the old labels of its entity type and role" do
      lens =
        resolved!([
          %{op: :rename_role, entity: Module39, from: :editor, to: :maintainer},
          %{op: :rename_entity, from: MyApp.Member, to: Module34},
          %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Staff}
        ])

      grant = fn entity_type, entity_id, role ->
        %{
          data: %{
            entity_id: entity_id,
            entity_type: entity_type && label(entity_type),
            id: @id_1,
            role: role,
            user_id: @id_2
          },
          id: @id_1,
          op: :put_entity,
          type: label(RoleGrant)
        }
      end

      [on_row, type_wide, global, untouched] =
        deltas(lens, [
          grant.(Module39, @id_2, "maintainer"),
          grant.(Module34, nil, "member"),
          grant.(nil, nil, "MyApp.Roles.Staff"),
          grant.(Module30, @id_2, "maintainer")
        ])

      assert {on_row.data.entity_type, on_row.data.role} == {label(Module39), "editor"}
      assert {type_wide.data.entity_type, type_wide.data.role} == {"MyApp.Member", "member"}
      assert {global.data.entity_type, global.data.role} == {nil, "MyApp.Roles.Admin"}
      assert {untouched.data.entity_type, untouched.data.role} == {label(Module30), "maintainer"}
    end

    test "a grants keep list passes as it is" do
      lens = resolved!([%{op: :add_role, entity: Module39, name: :guide, opts: []}])

      keep = %{
        data: %{hashes: ["0123456789abcdef"], salt: "s"},
        op: :keep_hashed,
        type: label(RoleGrant)
      }

      assert deltas(lens, [keep]) == [keep]
    end

    test "a grant of a role or an entity type new since is dropped" do
      lens =
        resolved!([
          %{op: :add_role, entity: Module39, name: :guide, opts: []},
          %{op: :create_entity, entity: Module30},
          %{op: :add_role, role: MyApp.Roles.Auditor, opts: []}
        ])

      grant = fn entity_type, role ->
        %{
          data: %{
            entity_type: entity_type && label(entity_type),
            id: @id_1,
            role: role,
            user_id: @id_2
          },
          id: @id_1,
          op: :put_entity,
          type: label(RoleGrant)
        }
      end

      assert deltas(lens, [
               grant.(Module39, "guide"),
               grant.(Module30, "owner"),
               grant.(nil, "MyApp.Roles.Auditor")
             ]) == []
    end

    test "a types marker names the old types, without those new since" do
      lens =
        resolved!([
          %{op: :rename_entity, from: MyApp.Member, to: Module34},
          %{op: :create_entity, entity: Module30}
        ])

      assert message(lens, {:sync_synced, {:types, [Module30, Module34, Module39]}, "c"}) ==
               {:sync_synced, {:types, [MyApp.Member, Module39]}, "c"}
    end

    test "any other message passes as it is" do
      lens = resolved!([])

      assert message(lens, {:sync_synced, :all, "c"}) == {:sync_synced, :all, "c"}
      assert message(lens, {:sync_resync, :model_hash}) == {:sync_resync, :model_hash}
    end
  end

  describe "servable?/2" do
    test "a row holding an enum value new since isn't servable" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      refute servable?(lens, %Module39{kind: :staff})
      assert servable?(lens, %Module39{kind: :guest})
      assert servable?(lens, %Module39{kind: nil})
      assert servable?(lens, %Module34{})
    end

    test "a row holding an enum value named new that the tab has is servable" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      assert servable?(lens, %Module39{kind: :new})
    end

    test "a row holding an enum value renamed away from new is servable, and told under new" do
      lens =
        lens!([
          %{op: :rename_enum_value, entity: Module39, attribute: :kind, from: :new, to: :guest}
        ])

      assert servable?(lens, %Module39{kind: :guest})

      put = %{
        data: %{id: @id_1, kind: "guest"},
        id: @id_1,
        op: :put_entity,
        type: label(Module39)
      }

      assert deltas(resolve(lens, @entity_types), [put]) == [
               %{put | data: %{id: @id_1, kind: "new"}}
             ]
    end

    test "a row of an enum attribute new since is servable, since the attribute is left out" do
      lens =
        lens!([
          %{op: :add_attribute, entity: Module39, name: :kind, type: :enum, opts: [values: [:a]]},
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      assert servable?(lens, %Module39{kind: :staff})
    end

    test "a grant naming an entity type or a role new since isn't servable" do
      lens =
        lens!([
          %{op: :add_role, entity: Module39, name: :guide, opts: []},
          %{op: :create_entity, entity: Module30},
          %{op: :add_role, role: MyApp.Roles.Auditor, opts: []}
        ])

      refute servable?(lens, %RoleGrant{entity_type: Module39, role: :guide})
      refute servable?(lens, %RoleGrant{entity_type: Module30, role: :owner})
      refute servable?(lens, %RoleGrant{entity_type: nil, role: MyApp.Roles.Auditor})
      assert servable?(lens, %RoleGrant{entity_type: Module39, role: :owner})
      assert servable?(lens, %RoleGrant{entity_type: nil, role: MyApp.Roles.Admin})
    end
  end

  describe "withholds?/2" do
    test "a type with an enum value new since can hold rows the tab is kept from" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      assert withholds?(lens, Module39)
      refute withholds?(lens, Module34)
      refute withholds?(lens, RoleGrant)
    end

    test "a type's enum values new since keep nothing from the tab when it never gets them" do
      new_attribute = [
        %{op: :add_attribute, entity: Module39, name: :kind, type: :enum, opts: [values: [:a]]},
        %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
      ]

      new_type = [
        %{op: :create_entity, entity: Module39},
        %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
      ]

      refute withholds?(lens!(new_attribute), Module39)
      refute withholds?(lens!(new_type), Module39)
    end

    test "a server-only attribute's values new since keep nothing from the tab" do
      # Module21's `balance` is server-only. The lens takes the ops as they come, so a value added
      # to it stands for one added to a server-only enum attribute, which the tab is never sent.
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module21, attribute: :balance, value: :x, opts: []}
        ])

      refute withholds?(lens, Module21)
      assert servable?(lens, %Module21{balance: :x})
    end

    test "grants can be kept from the tab once a role or an entity type is new" do
      refute withholds?(
               lens!([%{op: :rename_role, entity: Module39, from: :a, to: :b}]),
               RoleGrant
             )

      assert withholds?(
               lens!([%{op: :add_role, entity: Module39, name: :guide, opts: []}]),
               RoleGrant
             )

      assert withholds?(lens!([%{op: :add_role, role: MyApp.Roles.Auditor, opts: []}]), RoleGrant)
      assert withholds?(lens!([%{op: :create_entity, entity: Module30}]), RoleGrant)
    end
  end

  describe "servable_members/2" do
    test "a set leaves out the rows the tab is kept from" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      staff = %Module39{id: @id_1, kind: :staff}
      guest = %Module39{id: @id_2, kind: :guest}

      # Module40's `players` holds Module39 rows.
      row = %Module40{players: [staff, guest]}

      assert servable_members(lens, row) == %Module40{players: [guest]}
    end

    test "a set not read with the row is left as it is" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: Module39, attribute: :kind, value: :staff, opts: []}
        ])

      assert servable_members(lens, %Module40{}) == %Module40{}
    end
  end

  describe "for_hash/3" do
    # Three files: the first creates Module39 with `points`, the second renames it to `score`, the
    # third renames it back, so the first and the third record one hash.
    defp history(overrides \\ %{}) do
      migrations = [
        %{
          ops: [
            %{op: :create_entity, entity: Module39},
            %{op: :add_attribute, entity: Module39, name: :points, type: :integer, opts: []}
          ],
          version: "20260101000000"
        },
        %{
          ops: [%{op: :rename_attribute, entity: Module39, from: :points, to: :score}],
          version: "20260102000000"
        },
        %{
          ops: [%{op: :rename_attribute, entity: Module39, from: :score, to: :points}],
          version: "20260103000000"
        },
        %{
          ops: [%{op: :rename_attribute, entity: Module39, from: :points, to: :score}],
          version: "20260104000000"
        }
      ]

      recorded = %{
        "20260101000000" => "h1",
        "20260102000000" => "h2",
        "20260103000000" => "h1",
        "20260104000000" => "h2"
      }

      overrides
      |> Map.get(:recorded, recorded)
      |> history(Map.get(overrides, :migrations, migrations))
    end

    test "serves a hash from the latest point that records it" do
      assert {:ok, lens} = for_hash("h1", history(), @entity_types)

      assert old_attribute(lens, Module39, :score) == :points
      assert current_type(lens, label(Module39)) == Module39
    end

    test "serves the latest point, with no file after it, through a lens that changes nothing" do
      assert {:ok, lens} = for_hash("h2", history(), @entity_types)

      assert old_attribute(lens, Module39, :score) == :score
      assert old_type(lens, Module39) == Module39
    end

    # The second file swaps `points` and `score` through a temporary name, so the first two points
    # record one hash with each value under the other's name.
    test "serves nothing for a hash whose points translate otherwise" do
      migrations = [
        %{
          ops: [
            %{op: :create_entity, entity: Module39},
            %{op: :add_attribute, entity: Module39, name: :points, type: :integer, opts: []},
            %{op: :add_attribute, entity: Module39, name: :score, type: :integer, opts: []}
          ],
          version: "20260101000000"
        },
        %{
          ops: [
            %{op: :rename_attribute, entity: Module39, from: :points, to: :tmp},
            %{op: :rename_attribute, entity: Module39, from: :score, to: :points},
            %{op: :rename_attribute, entity: Module39, from: :tmp, to: :score}
          ],
          version: "20260102000000"
        },
        %{
          ops: [
            %{
              op: :add_attribute,
              entity: Module39,
              name: :bonus,
              type: :integer,
              opts: [optional: true]
            }
          ],
          version: "20260103000000"
        }
      ]

      recorded = %{
        "20260101000000" => "h1",
        "20260102000000" => "h1",
        "20260103000000" => "h3"
      }

      assert for_hash("h1", history(recorded, migrations), @entity_types) == :error
    end

    # The attribute the second file deletes, the third adds again: the first and the third record
    # one hash, but only the third is servable.
    test "serves nothing for a hash one of whose points is unservable" do
      readding = [
        %{
          ops: [
            %{op: :create_entity, entity: Module39},
            %{
              op: :add_attribute,
              entity: Module39,
              name: :points,
              type: :integer,
              opts: [optional: true]
            }
          ],
          version: "20260101000000"
        },
        %{
          ops: [%{op: :delete_attribute, entity: Module39, name: :points}],
          version: "20260102000000"
        },
        %{
          ops: [
            %{
              op: :add_attribute,
              entity: Module39,
              name: :points,
              type: :integer,
              opts: [optional: true]
            }
          ],
          version: "20260103000000"
        }
      ]

      recorded = %{
        "20260101000000" => "h1",
        "20260102000000" => "h2",
        "20260103000000" => "h1"
      }

      assert for_hash("h1", history(recorded, readding), @entity_types) == :error
    end

    test "serves nothing for a hash no point records" do
      assert for_hash("h9", history(), @entity_types) == :error
    end

    test "serves nothing from a point the release has no migration for" do
      %{migrations: migrations, recorded: recorded} = history()
      without_point = history(recorded, List.delete_at(migrations, 3))

      assert for_hash("h2", without_point, @entity_types) == :error
    end

    test "serves nothing from a point before a recorded version the release lacks" do
      %{migrations: migrations, recorded: recorded} = history()
      lacking = history(Map.put(recorded, "20260105000000", "h3"), migrations)

      assert for_hash("h1", lacking, @entity_types) == :error
    end

    # A tab built at the point held the file the release no longer has, so what the rest fold to
    # isn't what it read.
    test "serves nothing from a point after a recorded version the release lacks" do
      %{migrations: migrations, recorded: recorded} = history()
      lacking = history(Map.put(recorded, "20260101120000", "h0"), migrations)

      assert for_hash("h2", lacking, @entity_types) == :error
    end

    # A file removed before the point was applied is one the tab's build never held either.
    test "serves a point after a removed version when its files fold to the hash it recorded" do
      %{migrations: migrations} = history()

      recorded =
        migrations
        |> Enum.scan({nil, Model.empty()}, fn migration, {_version, model} ->
          {migration.version, Model.fold(model, migration.ops)}
        end)
        |> Map.new(fn {version, model} -> {version, Model.hash(model)} end)

      removed = Map.put(recorded, "20251231000000", "h0")
      first_hash = recorded["20260101000000"]

      assert {:ok, lens} = for_hash(first_hash, history(removed, migrations), @entity_types)
      assert old_attribute(lens, Module39, :score) == :points
    end

    # The tab was built between the two applied files, so the older one merged after them isn't
    # in its model, though it sorts before its point.
    test "serves nothing from a point an older file was applied after" do
      create = %{
        ops: [
          %{op: :create_entity, entity: Module39},
          %{op: :add_attribute, entity: Module39, name: :points, type: :integer, opts: []}
        ],
        version: "20260101000000"
      }

      late = %{
        ops: [%{op: :rename_attribute, entity: Module39, from: :points, to: :score}],
        version: "20260102000000"
      }

      added = %{
        ops: [
          %{
            op: :add_attribute,
            entity: Module39,
            name: :kind,
            type: :string,
            opts: [optional: true]
          }
        ],
        version: "20260103000000"
      }

      built_at =
        Model.empty()
        |> Model.fold(create.ops)
        |> Model.fold(added.ops)
        |> Model.hash()

      recorded = %{
        create.version => "h1",
        added.version => built_at,
        late.version => "h3"
      }

      applied = %{
        create.version => ~U[2026-01-01 00:00:00Z],
        added.version => ~U[2026-01-02 00:00:00Z],
        late.version => ~U[2026-01-03 00:00:00Z]
      }

      assert for_hash(built_at, history(recorded, [create, late, added], applied), @entity_types) ==
               :error
    end

    # The hash a clean history records can come from a Hologram that spelled the model another way.
    test "serves a point of files applied in order whatever hash it recorded" do
      %{migrations: migrations, recorded: recorded} = history()

      applied =
        recorded
        |> Map.keys()
        |> Enum.sort()
        |> Enum.with_index(1)
        |> Map.new(fn {version, day} ->
          {version, DateTime.add(~U[2026-01-01 00:00:00Z], day, :day)}
        end)

      assert {:ok, lens} = for_hash("h1", history(recorded, migrations, applied), @entity_types)
      assert old_attribute(lens, Module39, :score) == :points
    end

    test "serves nothing across a change renaming can't give back" do
      %{migrations: migrations, recorded: recorded} = history()

      deleting =
        List.replace_at(migrations, 3, %{
          ops: [%{op: :delete_attribute, entity: Module39, name: :points}],
          version: "20260104000000"
        })

      assert for_hash("h1", history(recorded, deleting), @entity_types) == :error
    end

    test "serves nothing from a point whose files a fold refuses" do
      %{migrations: migrations, recorded: recorded} = history()

      drafted =
        List.update_at(migrations, 0, fn migration ->
          draft = %{op: :resolve!, kind: :rename, payload: %{}, line: 1}

          %{migration | ops: [draft | migration.ops]}
        end)

      # The history's own fold would refuse it too, so the history is built from the files without
      # the draft, and the point folded through the drafted ones.
      history = %{history(recorded, migrations) | migrations: drafted}

      assert for_hash("h1", history, @entity_types) == :error
    end

    # A Hologram whose model term differs from the one that applied a file builds bundles under a
    # hash the table never recorded.
    test "serves a hash this Hologram works out for a point the table records another for" do
      %{migrations: migrations} = history()

      first_model = Model.fold(Model.empty(), hd(migrations).ops)

      assert {:ok, lens} =
               for_hash(Model.hash(first_model), history(), @entity_types)

      assert old_attribute(lens, Module39, :score) == :points
    end
  end

  describe "current_type/2" do
    test "an old label names the current type the tab's type became" do
      lens =
        resolved!([
          %{op: :rename_entity, from: MyApp.Member, to: Module34},
          %{op: :create_entity, entity: Module30}
        ])

      assert current_type(lens, "MyApp.Member") == Module34
      assert current_type(lens, label(Module39)) == Module39
      assert current_type(lens, label(Module34)) == nil
      assert current_type(lens, label(Module30)) == nil
      assert current_type(lens, "No.Such.Module.Anywhere") == nil
      assert current_type(lens, label(Hologram.Sync.Lens)) == nil
    end

    test "an old label of a type the current model doesn't list names nothing" do
      lens =
        [%{op: :rename_entity, from: MyApp.Member, to: MyApp.Unlisted}]
        |> lens!()
        |> resolve(@entity_types)

      assert current_type(lens, "MyApp.Member") == nil
    end
  end
end
