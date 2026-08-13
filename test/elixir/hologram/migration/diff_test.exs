defmodule Hologram.Migration.DiffTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Diff

  alias Hologram.Entity.Model

  defp model(entities, roles \\ %{}) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry =
          Map.merge(
            %{attributes: [], relationships: [], roles: []},
            entry_overrides
          )

        {entity_type, entry}
      end)

    %{entities: entries, roles: roles}
  end

  describe "diff/2" do
    test "returns an empty plan for equal models" do
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert diff(current, current) == %{ops: [], questions: []}
    end

    test "emits creation ops for a created entity type" do
      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:priority, :integer, [optional: true]}, {:title, :string, []}],
            relationships: [{:author, MyApp.User, []}],
            roles: [{:editor, []}]
          }
        })

      assert diff(Model.empty(), current) == %{
               ops: [
                 %{op: :create_entity, entity: MyApp.Task},
                 %{
                   op: :add_attribute,
                   entity: MyApp.Task,
                   name: :priority,
                   type: :integer,
                   opts: [optional: true]
                 },
                 %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: []},
                 %{
                   op: :add_relationship,
                   entity: MyApp.Task,
                   name: :author,
                   type: MyApp.User,
                   opts: []
                 },
                 %{op: :add_role, entity: MyApp.Task, name: :editor, opts: []}
               ],
               questions: []
             }
    end

    test "emits a deletion op for a deleted entity type" do
      replayed = model(%{MyApp.Archive => %{}})

      assert diff(replayed, Model.empty()) == %{
               ops: [%{op: :delete_entity, entity: MyApp.Archive}],
               questions: []
             }
    end

    test "withholds entity creations and deletions into a question" do
      replayed = model(%{MyApp.Draft => %{attributes: [{:body, :string, []}]}})

      current =
        model(%{
          MyApp.Marker => %{},
          MyApp.Sketch => %{attributes: [{:body, :string, []}]}
        })

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :entities,
                   deleted: [MyApp.Draft],
                   created: [MyApp.Marker, MyApp.Sketch],
                   hints: [{:rename, MyApp.Draft, MyApp.Sketch}],
                   withheld_ops: [
                     %{op: :create_entity, entity: MyApp.Marker},
                     %{op: :create_entity, entity: MyApp.Sketch},
                     %{
                       op: :add_attribute,
                       entity: MyApp.Sketch,
                       name: :body,
                       type: :string,
                       opts: []
                     },
                     %{op: :delete_entity, entity: MyApp.Draft}
                   ]
                 }
               ]
             }
    end

    test "emits global role ops" do
      replayed =
        model(%{}, %{
          MyApp.Roles.Admin => %{extends: []},
          MyApp.Roles.Owner => %{extends: []}
        })

      current =
        model(%{}, %{
          MyApp.Roles.Admin => %{extends: []},
          MyApp.Roles.Owner => %{extends: [MyApp.Roles.Admin]},
          MyApp.Roles.Support => %{extends: [MyApp.Roles.Admin]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :add_role,
                   role: MyApp.Roles.Support,
                   opts: [extends: [MyApp.Roles.Admin]]
                 },
                 %{
                   op: :change_role,
                   role: MyApp.Roles.Owner,
                   changes: [extends: [MyApp.Roles.Admin]]
                 }
               ],
               questions: []
             }
    end

    test "spells a global role losing its extends as the neutral value" do
      replayed = model(%{}, %{MyApp.Roles.Owner => %{extends: [MyApp.Roles.Admin]}})
      current = model(%{}, %{MyApp.Roles.Owner => %{extends: []}})

      assert diff(replayed, current) == %{
               ops: [%{op: :change_role, role: MyApp.Roles.Owner, changes: [extends: nil]}],
               questions: []
             }
    end

    test "withholds global role additions and deletions into a question" do
      replayed =
        model(%{}, %{
          MyApp.Roles.Moderator => %{extends: []},
          MyApp.Roles.Owner => %{extends: []}
        })

      current =
        model(%{}, %{
          MyApp.Roles.Maintainer => %{extends: []},
          MyApp.Roles.Owner => %{extends: [MyApp.Roles.Maintainer]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_role,
                   role: MyApp.Roles.Owner,
                   changes: [extends: [MyApp.Roles.Maintainer]]
                 }
               ],
               questions: [
                 %{
                   kind: :roles,
                   deleted: [MyApp.Roles.Moderator],
                   added: [MyApp.Roles.Maintainer],
                   hints: [{:rename, MyApp.Roles.Moderator, MyApp.Roles.Maintainer}],
                   withheld_ops: [
                     %{op: :add_role, role: MyApp.Roles.Maintainer, opts: []},
                     %{op: :delete_role, role: MyApp.Roles.Moderator}
                   ]
                 }
               ]
             }
    end
  end
end
