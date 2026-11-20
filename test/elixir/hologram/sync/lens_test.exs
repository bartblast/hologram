defmodule Hologram.Sync.LensTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Lens

  alias Hologram.Sync.Lens

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

      assert old_type(lens, @stop) == :new
      assert old_attribute(lens, @stop, :city) == :new
      assert old_relationship(lens, @stop, :trip) == :new
      assert old_enum_value(lens, @stop, :kind, :bus) == :new
      assert old_role(lens, @stop, :guide) == :new
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

      assert old_type(lens, @journey) == :new
      assert old_attribute(lens, @journey, :city) == :new
    end

    test "an added attribute is new" do
      lens = lens!([%{op: :add_attribute, entity: @trip, name: :notes, type: :string, opts: []}])

      assert old_attribute(lens, @trip, :notes) == :new
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
      assert old_attribute(lens, @trip, :destination) == :new
    end

    test "an added attribute renamed later stays new" do
      lens =
        lens!([
          %{op: :add_attribute, entity: @trip, name: :notes, type: :string, opts: []},
          %{op: :rename_attribute, entity: @trip, from: :notes, to: :remarks}
        ])

      assert old_attribute(lens, @trip, :remarks) == :new
    end

    test "an added relationship is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_relationship, entity: @trip, name: :stops, type: [@stop], opts: []},
          %{op: :rename_relationship, entity: @trip, from: :owner, to: :organizer}
        ])

      assert old_relationship(lens, @trip, :stops) == :new
      assert old_relationship(lens, @trip, :organizer) == :owner
      assert old_relationship(lens, @trip, :owner) == :owner
    end

    test "an added enum value is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_enum_value, entity: @trip, attribute: :status, value: :cancelled, opts: []},
          %{op: :rename_enum_value, entity: @trip, attribute: :status, from: :done, to: :finished}
        ])

      assert old_enum_value(lens, @trip, :status, :cancelled) == :new
      assert old_enum_value(lens, @trip, :status, :finished) == :done
      assert old_enum_value(lens, @trip, :status, :draft) == :draft
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

      assert old_enum_value(lens, @trip, :state, :cancelled) == :new
      assert old_enum_value(lens, @trip, :state, :finished) == :done
      assert old_enum_value(lens, @trip, :status, :cancelled) == :cancelled
    end

    test "any value of an added enum attribute is new" do
      lens =
        lens!([
          %{op: :add_attribute, entity: @trip, name: :kind, type: :enum, opts: [values: [:a]]}
        ])

      assert old_enum_value(lens, @trip, :kind, :a) == :new
    end

    test "an added entity role is new, a renamed one keeps its old name" do
      lens =
        lens!([
          %{op: :add_role, entity: @trip, name: :guide, opts: []},
          %{op: :rename_role, entity: @trip, from: :editor, to: :maintainer}
        ])

      assert old_role(lens, @trip, :guide) == :new
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

      assert old_global_role(lens, auditor) == :new
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

        assert old_attribute(lens, @trip, :budget) == :new
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

      assert old_attribute(lens, @journey, :cost) == :new
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
end
