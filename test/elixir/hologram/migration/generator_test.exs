defmodule Hologram.Migration.GeneratorTest do
  # async: false - resolve!-free generate outcomes shadow-verify against the scratch
  # database, a per-suite singleton (the configured name + "_shadow").
  #
  # The tests tagged :database are the ones that shadow-verify: the verifier opens its own
  # connection to the server, so they need one, whatever the suite booted.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Migration.Generator

  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader
  alias Hologram.Reflection

  @tmp_dir Path.join([Reflection.tmp_dir(), "tests", "migration", "generator"])

  @module MyApp.Migrations.V20260813091522

  @timestamp ~U[2026-08-13 09:15:22Z]

  # Compiles the module the given plan renders to, as the generator compiles a written file,
  # and returns its ops.
  defp compile_rendered(plan) do
    module = written_module(random_module())

    plan
    |> render(module)
    |> Code.compile_string("app/migrations/20260813091522.ex")

    module.__hologram_migration__().ops
  end

  defp history(files) do
    files
    |> Enum.map(fn {version, body} -> compile_migration(version, body) end)
    |> Loader.from_modules!()
  end

  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry =
          Map.merge(%{attributes: [], relationships: [], roles: [], uniques: []}, entry_overrides)

        {entity_type, entry}
      end)

    %{entities: entries, roles: %{}, user_entity: nil}
  end

  defp module_text(module, body) do
    indented_body =
      body
      |> normalize_newlines()
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map_join("\n", fn
        "" -> ""
        line -> "  " <> line
      end)

    # Normalized as a whole: on Windows this file is checked out with CRLF line endings, so
    # the heredoc's own lines carry them, while the generator writes LF.
    normalize_newlines("""
    defmodule #{inspect(module)} do
      @moduledoc false

      use Hologram.Migration

    #{indented_body}
    end
    """)
  end

  # The directory a test's generated file is written to, and a namespace no other test's
  # modules use.
  defp opts!(test_dir) do
    dir = Path.join([@tmp_dir, test_dir, "app", "migrations"])

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    [dir: dir, namespace: random_module()]
  end

  # The module of the migration written at @timestamp into the given namespace.
  defp written_module(namespace) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(namespace, "V20260813091522")
  end

  describe "generate/4" do
    @tag :database
    test "writes the migration taking the history to the model" do
      opts = opts!("writes_migration")
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 0} = generate([], current, @timestamp, opts)
      assert path == Path.join(opts[:dir], "20260813091522.ex")

      expected = """
      create_entity MyApp.Task do
        add_attribute :title, :string
      end
      """

      module = written_module(opts[:namespace])

      assert File.read!(path) == module_text(module, expected)
    end

    @tag :database
    test "writes a key after the members it names, in a history that builds its index" do
      opts = opts!("writes_key")

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            uniques: [[:slug, :kind]]
          }
        })

      assert {:ok, path, 0} = generate([], current, @timestamp, opts)

      expected = """
      create_entity MyApp.Task do
        add_attribute :kind, :string
        add_attribute :slug, :string
        add_unique [:slug, :kind]
      end
      """

      module = written_module(opts[:namespace])

      assert File.read!(path) == module_text(module, expected)

      migrations = Loader.from_modules!([module])

      assert generate(migrations, current, ~U[2026-08-13 10:15:22Z], opts) == :nothing_to_do
    end

    @tag :database
    test "finds nothing to do once a key's field is renamed in the history" do
      opts = opts!("key_follows_rename")

      create_body = """
      create_entity MyApp.Task do
        add_attribute :kind, :string
        add_attribute :name, :string
        add_unique [:kind, :name]
      end
      """

      rename_body = """
      change_entity MyApp.Task do
        rename_attribute :name, :title
      end
      """

      migrations = history([{"20260813091521", create_body}, {"20260813091522", rename_body}])

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:title, :string, []}],
            uniques: [[:kind, :title]]
          }
        })

      assert generate(migrations, current, ~U[2026-08-13 11:15:22Z], opts) == :nothing_to_do
      assert File.ls!(opts[:dir]) == []
    end

    @tag :database
    test "names the module after the namespace of the newest migration in the directory" do
      opts = opts!("newest_namespace")
      namespace = random_module()
      newest_path = Path.join(opts[:dir], "20260813091521.ex")

      File.write!(newest_path, """
      defmodule #{inspect(namespace)}.V20260813091521 do
        use Hologram.Migration

        create_entity MyApp.Task
      end
      """)

      [{newest, _bytecode}] = Code.compile_file(newest_path)
      migrations = Loader.from_modules!([newest])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, [optional: true]}]}})

      assert {:ok, path, 0} = generate(migrations, current, @timestamp, opts)
      assert File.read!(path) =~ "defmodule #{inspect(written_module(namespace))} do"
    end

    @tag :database
    test "takes the given namespace while the directory holds no migration" do
      opts = opts!("outside_namespace")

      # Compiled as though in another app's app/migrations/ - an umbrella sibling's.
      migrations = history([{"20260813091521", "create_entity MyApp.Task"}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, [optional: true]}]}})

      assert {:ok, path, 0} = generate(migrations, current, @timestamp, opts)
      assert File.read!(path) =~ "defmodule #{inspect(written_module(opts[:namespace]))} do"
    end

    @tag :database
    test "writes a to-one replaced by an attribute taking its column" do
      opts = opts!("takes_column")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Place

           create_entity MyApp.Task do
             add_relationship :place, MyApp.Place, optional: true
           end
           """}
        ])

      current =
        model(%{
          MyApp.Place => %{},
          MyApp.Task => %{attributes: [{:place_id, :uuid, [optional: true]}]}
        })

      assert {:ok, path, 0} = generate(migrations, current, @timestamp, opts)

      written = File.read!(path)

      assert written =~ "add_attribute :place_id, :uuid"
      assert written =~ "delete_relationship :place"
    end

    # A backfill applies apart from the ops around it, so the answer can't take the column while
    # the to-one below it still holds it. Each case gives the lines freeing the column and the
    # edits answering the draft.
    fill = "resolve! :fill, attributes: [:place_id]"
    delete = "delete_relationship :place"
    to_many = "change_relationship :place, type: [MyApp.Place]"

    for {label, current_extra, freeing_lines, edits} <- [
          {"a deleted to-one, answered from a value", %{}, [delete],
           [{fill, "add_attribute :place_id, :id, backfill: backup_id"}]},
          {"a deleted to-one, answered from it renamed", %{}, [delete],
           [
             {"#{delete}\n    # RESOLVE",
              "rename_relationship :place, :old_place\n    # RESOLVE"},
             {fill,
              "add_attribute :place_id, :id, backfill: old_place.id\n" <>
                "    delete_relationship :old_place"}
           ]},
          {"a to-one turning to-many, answered from a value",
           %{relationships: [{:place, [MyApp.Place], [optional: true]}]}, [to_many],
           [{fill, "add_attribute :place_id, :id, backfill: backup_id"}]},
          {"a to-one turning to-many, answered from it renamed",
           %{relationships: [{:place, [MyApp.Place], [optional: true]}]}, [to_many],
           [
             {"#{to_many}\n    # RESOLVE",
              "rename_relationship :place, :old_place\n    # RESOLVE"},
             {fill,
              "add_attribute :place_id, :id, backfill: old_place.id\n" <>
                "    change_relationship :old_place, type: [MyApp.Place]\n" <>
                "    rename_relationship :old_place, :place"}
           ]},
          {"a to-one an answer deletes, answered from a value",
           %{relationships: [{:venue, MyApp.Place, [optional: true]}]}, [],
           [
             {"resolve! :relationships, deleted: [:place], added: [:venue]",
              "delete_relationship :place\n" <>
                "    add_relationship :venue, MyApp.Place, optional: true"},
             {fill, "add_attribute :place_id, :id, backfill: backup_id"}
           ]},
          {"a to-one an answer deletes, answered from it renamed",
           %{relationships: [{:venue, MyApp.Place, [optional: true]}]}, [],
           [
             {"resolve! :relationships, deleted: [:place], added: [:venue]",
              "rename_relationship :place, :old_place\n" <>
                "    add_relationship :venue, MyApp.Place, optional: true"},
             {fill,
              "add_attribute :place_id, :id, backfill: old_place.id\n" <>
                "    delete_relationship :old_place"}
           ]}
        ] do
      @tag :database
      test "lets a fill take a column a to-one frees: #{label}" do
        opts = opts!("takes_column_required")

        migrations =
          history([
            {"20260813091521",
             """
             create_entity MyApp.Place

             create_entity MyApp.Task do
               add_relationship :place, MyApp.Place, optional: true
               add_attribute :backup_id, :id, default: "0000000000000000000001"
             end
             """}
          ])

        task =
          Map.merge(
            %{attributes: [], relationships: []},
            unquote(Macro.escape(current_extra)),
            fn _key, left, right -> left ++ right end
          )

        current =
          model(%{
            MyApp.Place => %{},
            MyApp.Task => %{
              task
              | attributes:
                  Enum.sort([
                    {:backup_id, :id, [default: "0000000000000000000001"]},
                    {:place_id, :id, []} | task.attributes
                  ])
            }
          })

        assert {:ok, path, _question_count} = generate(migrations, current, @timestamp, opts)

        draft = File.read!(path)

        for line <- unquote(freeing_lines) do
          assert draft =~ ~r/#{Regex.escape(line)}\n *# RESOLVE: :place_id is required/
          assert draft =~ "#   #{line}\n"
        end

        answered =
          Enum.reduce(unquote(edits), draft, fn {from, to}, text ->
            assert [_before, _after] = String.split(text, from)
            String.replace(text, from, to)
          end)

        File.write!(path, answered)
        Code.compile_file(path)

        [migration] = Loader.from_modules!([written_module(opts[:namespace])])
        history = Enum.concat(migrations, [migration])

        assert generate(history, current, @timestamp, opts) == :nothing_to_do
      end
    end

    # Only the final model is free of a required cycle, so the swap must not split the file into
    # parts that each have to stand.
    @tag :database
    test "writes that replacement beside a required cycle moving to another side" do
      opts = opts!("takes_column_cycle")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Alpha
           create_entity MyApp.Beta
           create_entity MyApp.Place

           change_entity MyApp.Alpha do
             add_relationship :b, MyApp.Beta, optional: true
           end

           change_entity MyApp.Beta do
             add_relationship :a, MyApp.Alpha
             add_relationship :place, MyApp.Place, optional: true
           end
           """}
        ])

      current =
        model(%{
          MyApp.Alpha => %{relationships: [{:b, MyApp.Beta, []}]},
          MyApp.Beta => %{
            attributes: [{:place_id, :uuid, [optional: true]}],
            relationships: [{:a, MyApp.Alpha, [optional: true]}]
          },
          MyApp.Place => %{}
        })

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)

      answered =
        path
        |> File.read!()
        |> String.replace(
          ~r/^( *)resolve! :fill, attributes: \[:b\]$/m,
          "\\1change_relationship :b, optional: false"
        )

      refute answered =~ ~r/^ *resolve!/m

      File.write!(path, answered)
      Code.compile_file(path)

      [migration] = Loader.from_modules!([written_module(opts[:namespace])])
      history = Enum.concat(migrations, [migration])

      assert generate(history, current, @timestamp, opts) == :nothing_to_do
    end

    # A backfill applies apart from the ops around it, so the relaxation ending the cycle is
    # written above the question.
    @tag :database
    test "writes a relaxation ending a required cycle above a fill a backfill answers" do
      opts = opts!("backfilled_cycle")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Alpha
           create_entity MyApp.Beta
           create_entity MyApp.Place

           change_entity MyApp.Alpha do
             add_relationship :b, MyApp.Beta, optional: true
           end

           change_entity MyApp.Beta do
             add_relationship :a, MyApp.Alpha
             add_relationship :place, MyApp.Place, optional: true
           end
           """}
        ])

      current =
        model(%{
          MyApp.Alpha => %{relationships: [{:b, MyApp.Beta, []}]},
          MyApp.Beta => %{
            attributes: [{:place_id, :uuid, [optional: true]}],
            relationships: [{:a, MyApp.Alpha, [optional: true]}]
          },
          MyApp.Place => %{}
        })

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)

      answered =
        path
        |> File.read!()
        |> String.replace(
          ~r/^( *)resolve! :fill, attributes: \[:b\]$/m,
          "\\1change_relationship :b, optional: false, backfill: ^\"02wndAAHBC95f4Al8rNFlA\""
        )

      refute answered =~ ~r/^ *resolve!/m

      File.write!(path, answered)
      Code.compile_file(path)

      [migration] = Loader.from_modules!([written_module(opts[:namespace])])
      history = Enum.concat(migrations, [migration])

      assert generate(history, current, @timestamp, opts) == :nothing_to_do
    end

    # The blocks asking for a fill are written by name, so a relaxation in a later one is written
    # above all of them - with the other changes it makes to the member, too.
    for {label, dir, changes, text} <- [
          {"alone", "backfilled_cross_block_cycle", [optional: true], "optional: true"},
          {"beside another change", "backfilled_cross_block_cycle_unique",
           [optional: true, unique: true], "optional: true, unique: true"}
        ] do
      @tag :database
      test "writes a relaxation #{label} ending a required cycle above another block's fill a backfill answers" do
        opts = opts!(unquote(dir))

        migrations =
          history([
            {"20260813091521",
             """
             create_entity MyApp.Alpha
             create_entity MyApp.Beta
             create_entity MyApp.Place

             change_entity MyApp.Alpha do
               add_relationship :b, MyApp.Beta, optional: true
             end

             change_entity MyApp.Beta do
               add_relationship :a, MyApp.Alpha
               add_relationship :place, MyApp.Place, optional: true
             end
             """}
          ])

        current =
          model(%{
            MyApp.Alpha => %{relationships: [{:b, MyApp.Beta, []}]},
            MyApp.Beta => %{
              relationships: [{:a, MyApp.Alpha, unquote(changes)}, {:place, MyApp.Place, []}]
            },
            MyApp.Place => %{}
          })

        assert {:ok, path, 2} = generate(migrations, current, @timestamp, opts)

        assert File.read!(path) =~
                 "change_entity MyApp.Beta do\n    change_relationship :a, #{unquote(text)}\n  end\n\n" <>
                   "  change_entity MyApp.Alpha do"

        answered =
          path
          |> File.read!()
          |> String.replace(
            ~r/^( *)resolve! :fill, attributes: \[:(b|place)\]$/m,
            "\\1change_relationship :\\2, optional: false, backfill: ^\"02wndAAHBC95f4Al8rNFlA\""
          )

        refute answered =~ ~r/^ *resolve!/m

        File.write!(path, answered)
        Code.compile_file(path)

        [migration] = Loader.from_modules!([written_module(opts[:namespace])])
        history = Enum.concat(migrations, [migration])

        assert generate(history, current, @timestamp, opts) == :nothing_to_do
      end
    end

    # A delete can't go above the fills, since the block's own backfill can read what it takes
    # away, so the note says where to write it when another block's backfill needs it.
    @tag :database
    test "notes a delete ending a required cycle that another block's fill a backfill answers needs" do
      opts = opts!("backfilled_cross_block_cycle_delete")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Alpha
           create_entity MyApp.Beta
           create_entity MyApp.Place

           change_entity MyApp.Alpha do
             add_relationship :b, MyApp.Beta, optional: true
           end

           change_entity MyApp.Beta do
             add_relationship :a, MyApp.Alpha
             add_relationship :place, MyApp.Place, optional: true
           end
           """}
        ])

      current =
        model(%{
          MyApp.Alpha => %{relationships: [{:b, MyApp.Beta, []}]},
          MyApp.Beta => %{relationships: [{:place, MyApp.Place, []}]},
          MyApp.Place => %{}
        })

      assert {:ok, path, 2} = generate(migrations, current, @timestamp, opts)

      written = File.read!(path)

      assert written =~
               "    # If one of these ends a cycle of required to-ones that a line above closes, " <>
                 "write it in a change_entity block of its own above that line, with the " <>
                 "delete_unique lines naming it - unless this block's backfill reads what it " <>
                 "takes away:\n" <>
                 "    #   delete_relationship :a\n"

      # Following the note: the delete moves to a block of its own above Alpha's.
      answered =
        written
        |> String.replace(~r/^    delete_relationship :a\n/m, "")
        |> String.replace(
          "  change_entity MyApp.Alpha do",
          "  change_entity MyApp.Beta do\n    delete_relationship :a\n  end\n\n  change_entity MyApp.Alpha do"
        )
        |> String.replace(
          ~r/^( *)resolve! :fill, attributes: \[:(b|place)\]$/m,
          "\\1change_relationship :\\2, optional: false, backfill: ^\"02wndAAHBC95f4Al8rNFlA\""
        )

      refute answered =~ ~r/^ *resolve!/m

      File.write!(path, answered)
      Code.compile_file(path)

      [migration] = Loader.from_modules!([written_module(opts[:namespace])])
      history = Enum.concat(migrations, [migration])

      assert generate(history, current, @timestamp, opts) == :nothing_to_do
    end

    # The blocks asking for a fill come after the others, so a retarget in another block can close
    # a cycle a delete in the first of them ends.
    @tag :database
    test "notes a delete ending a required cycle that a retarget above closes" do
      opts = opts!("retargeted_cycle_delete")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Alpha
           create_entity MyApp.Gamma
           create_entity MyApp.Other

           change_entity MyApp.Alpha do
             add_attribute :title, :string, optional: true
             add_relationship :e, MyApp.Gamma
           end

           change_entity MyApp.Gamma do
             add_relationship :g, MyApp.Other
           end
           """}
        ])

      current =
        model(%{
          MyApp.Alpha => %{attributes: [{:title, :string, []}]},
          MyApp.Gamma => %{relationships: [{:g, MyApp.Alpha, []}]},
          MyApp.Other => %{}
        })

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)

      written = File.read!(path)

      assert written =~
               "change_entity MyApp.Gamma do\n    change_relationship :g, type: MyApp.Alpha\n  end"

      assert written =~
               "    # If one of these ends a cycle of required to-ones that a line above closes, " <>
                 "write it in a change_entity block of its own above that line, with the " <>
                 "delete_unique lines naming it - unless this block's backfill reads what it " <>
                 "takes away:\n" <>
                 "    #   delete_relationship :e\n"

      # Following the note: the delete moves to a block of its own above Gamma's.
      answered =
        written
        |> String.replace(~r/^    delete_relationship :e\n/m, "")
        |> String.replace(
          "  change_entity MyApp.Gamma do",
          "  change_entity MyApp.Alpha do\n    delete_relationship :e\n  end\n\n  change_entity MyApp.Gamma do"
        )
        |> String.replace(
          ~r/^( *)resolve! :fill, attributes: \[:title\]$/m,
          "\\1change_attribute :title, optional: false, backfill: \"untitled\""
        )

      refute answered =~ ~r/^ *resolve!/m

      File.write!(path, answered)
      Code.compile_file(path)

      [migration] = Loader.from_modules!([written_module(opts[:namespace])])
      history = Enum.concat(migrations, [migration])

      assert generate(history, current, @timestamp, opts) == :nothing_to_do
    end

    # A block asking no fill comes before the fill blocks, so a retarget there can close a cycle
    # that a relaxation from a fill block ends.
    @tag :database
    test "writes a relaxation ending a required cycle above a retarget closing it" do
      opts = opts!("retargeted_cycle_relaxation")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Zeta
           create_entity MyApp.Gamma
           create_entity MyApp.Other

           change_entity MyApp.Zeta do
             add_attribute :title, :string, optional: true
             add_relationship :e, MyApp.Gamma
           end

           change_entity MyApp.Gamma do
             add_relationship :g, MyApp.Other
           end
           """}
        ])

      current =
        model(%{
          MyApp.Zeta => %{
            attributes: [{:title, :string, []}],
            relationships: [{:e, MyApp.Gamma, [optional: true]}]
          },
          MyApp.Gamma => %{relationships: [{:g, MyApp.Zeta, []}]},
          MyApp.Other => %{}
        })

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)

      written = File.read!(path)

      assert written =~
               "  change_entity MyApp.Zeta do\n" <>
                 "    change_relationship :e, optional: true\n" <>
                 "  end\n\n" <>
                 "  change_entity MyApp.Gamma do\n" <>
                 "    change_relationship :g, type: MyApp.Zeta\n" <>
                 "  end\n"

      answered =
        String.replace(
          written,
          ~r/^( *)resolve! :fill, attributes: \[:title\]$/m,
          "\\1change_attribute :title, optional: false, backfill: \"untitled\""
        )

      refute answered =~ ~r/^ *resolve!/m

      File.write!(path, answered)
      Code.compile_file(path)

      [migration] = Loader.from_modules!([written_module(opts[:namespace])])
      history = Enum.concat(migrations, [migration])

      assert generate(history, current, @timestamp, opts) == :nothing_to_do
    end

    @tag :database
    test "formats the file with the given formatter" do
      opts =
        "formatter"
        |> opts!()
        |> Keyword.put(:format, &(&1 <> "# formatted\n"))

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 0} = generate([], current, @timestamp, opts)

      # Normalized: the given formatter is the only one, and on Windows the generator's own
      # source carries CRLF line endings that a real formatter would turn into LF.
      assert path
             |> File.read!()
             |> normalize_newlines()
             |> String.ends_with?("end\n# formatted\n")
    end

    test "leaves no file behind when the written migration fails to compile" do
      refusing_format =
        &String.replace(&1, "@moduledoc false", "@moduledoc false\nraise \"refused\"")

      opts =
        "uncompilable"
        |> opts!()
        |> Keyword.put(:format, refusing_format)

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert_raise RuntimeError, "refused", fn -> generate([], current, @timestamp, opts) end

      assert File.ls!(opts[:dir]) == []
    end

    test "returns the question count of a generated draft" do
      opts = opts!("draft_count")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Task do
             add_attribute :name, :string
           end
           """}
        ])

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)

      assert path
             |> File.read!()
             |> String.contains?("resolve! :attributes")
    end

    test "keeps a generated draft in a build that refuses drafts" do
      env = Mix.env()
      on_exit(fn -> Mix.env(env) end)
      Mix.env(:prod)

      opts = opts!("draft_prod_build")
      migrations = history([{"20260813091521", "create_entity MyApp.Task"}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 1} = generate(migrations, current, @timestamp, opts)
      assert File.ls!(opts[:dir]) == [Path.basename(path)]
    end

    @tag :database
    test "does nothing when the history already produces the model" do
      opts = opts!("nothing_to_do")

      migrations =
        history([
          {"20260813091521",
           """
           create_entity MyApp.Task do
             add_attribute :title, :string
           end
           """}
        ])

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert generate(migrations, current, @timestamp, opts) == :nothing_to_do
      assert File.ls!(opts[:dir]) == []
    end

    @tag :database
    test "writes an option's regex with the modifiers it was declared with" do
      opts = opts!("regex_option")

      current =
        model(%{
          MyApp.Task => %{attributes: [{:title, :string, [format: {:regex, "^a", [:caseless]}]}]}
        })

      assert {:ok, path, 0} = generate([], current, @timestamp, opts)

      expected = """
      create_entity MyApp.Task do
        add_attribute :title, :string, format: ~r/^a/i
      end
      """

      module = written_module(opts[:namespace])

      assert File.read!(path) == module_text(module, expected)
    end

    @tag :database
    test "the history it writes for a model holding a regex produces that model" do
      opts = opts!("regex_round_trip")

      current =
        model(%{MyApp.Task => %{attributes: [{:title, :string, [format: {:regex, "^a", []}]}]}})

      assert {:ok, _path, 0} = generate([], current, @timestamp, opts)

      module = written_module(opts[:namespace])
      replayed = Model.fold(Model.empty(), module.__hologram_migration__().ops)

      assert replayed == current
    end

    @tag :database
    test "bumps the version while a migration holds it" do
      opts = opts!("bumps_version")
      migrations = history([{"20260813091522", ""}])
      current = model(%{MyApp.Task => %{}})

      assert {:ok, path, 0} = generate(migrations, current, @timestamp, opts)
      assert path == Path.join(opts[:dir], "20260813091523.ex")
    end

    @tag :database
    test "bumps the version while a file holds it" do
      opts = opts!("bumps_version_file")

      opts[:dir]
      |> Path.join("20260813091522.ex")
      |> File.write!("")

      current = model(%{MyApp.Task => %{}})

      assert {:ok, path, 0} = generate([], current, @timestamp, opts)
      assert path == Path.join(opts[:dir], "20260813091523.ex")
    end

    test "refuses to generate while a draft holds unanswered questions" do
      opts = opts!("unresolved")

      migrations =
        history([
          {"20260813091522",
           """
           change_entity MyApp.Task do
             resolve! :attributes, deleted: [:name], added: [:title]
           end
           """}
        ])

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:error, {:unresolved, [{path, op}]}} =
               generate(migrations, current, @timestamp, opts)

      assert path == "app/migrations/20260813091522.ex"
      assert op.kind == :attributes
      assert op.line == 5
      assert File.ls!(opts[:dir]) == []
    end

    @tag :database
    test "refuses a resolved history that cannot build the model's schema" do
      create_body = """
      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      narrow_body = """
      change_entity MyApp.Task do
        change_relationship :tags, type: MyApp.Tag
      end
      """

      opts = opts!("narrowing")
      migrations = history([{"20260813091522", create_body}, {"20260813091523", narrow_body}])

      current =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}
        })

      expected_msg =
        "changing relationship :tags on MyApp.Task from to-many to to-one is not " <>
          "supported - a row holding several targets has no one target to keep - " <>
          "delete the relationship and add it with the new cardinality, or write " <>
          "the migration that picks the survivors"

      assert_error Hologram.CompileError, expected_msg, fn ->
        generate(migrations, current, @timestamp, opts)
      end
    end

    @tag :database
    test "leaves no file or module behind when the written migration fails verification" do
      create_body = """
      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      opts = opts!("unverifiable")
      migrations = history([{"20260813091521", create_body}])

      current =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}
        })

      written_module = written_module(opts[:namespace])

      assert_raise Hologram.CompileError, fn ->
        generate(migrations, current, @timestamp, opts)
      end

      # The rejected file would otherwise become the next run's history, which replays the
      # ops that failed and reports the same error with nothing naming the cause.
      assert File.ls!(opts[:dir]) == []
      assert :code.is_loaded(written_module) == false
    end

    @tag :database
    test "verifies the written migration at its place in version order" do
      opts = opts!("version_order")
      migrations = history([{"20270101000000", "create_entity MyApp.Task"}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, [optional: true]}]}})

      # The written file sorts before the existing one, so its change to MyApp.Task replays
      # before MyApp.Task exists.
      assert_raise Hologram.CompileError, ~r/no such entity MyApp\.Task/, fn ->
        generate(migrations, current, @timestamp, opts)
      end

      assert File.ls!(opts[:dir]) == []
    end
  end

  describe "render/3" do
    test "renders entity blocks in alphabetical order after the renames" do
      plan = %{
        ops: [
          %{op: :create_entity, entity: MyApp.Comment},
          %{op: :add_attribute, entity: MyApp.Comment, name: :body, type: :string, opts: []},
          %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch},
          %{op: :rename_attribute, entity: MyApp.Task, from: :name, to: :title},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [optional: true]
          },
          %{op: :delete_entity, entity: MyApp.Archive}
        ],
        questions: []
      }

      expected = """
      rename_entity MyApp.Draft, MyApp.Sketch

      create_entity MyApp.Comment do
        add_attribute :body, :string
      end

      change_entity MyApp.Task do
        rename_attribute :name, :title
        add_attribute :priority, :integer, optional: true
      end

      delete_entity MyApp.Archive
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders the user entity designation after the entity blocks" do
      plan = %{
        ops: [
          %{op: :create_entity, entity: MyApp.Account},
          %{op: :add_attribute, entity: MyApp.Account, name: :email, type: :string, opts: []},
          %{op: :designate_user_entity, entity: MyApp.Account}
        ],
        questions: []
      }

      expected = """
      create_entity MyApp.Account do
        add_attribute :email, :string
      end

      designate_user_entity MyApp.Account
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders the role grant deletion, the one op carrying parens" do
      plan = %{ops: [%{op: :delete_role_grants}], questions: []}

      expected = """
      delete_role_grants()
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders a removed user entity designation as nil" do
      plan = %{ops: [%{op: :designate_user_entity, entity: nil}], questions: []}

      expected = """
      designate_user_entity nil
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders a moved designation question with both ops the answer needs" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :user_entity,
            from: MyApp.User,
            to: MyApp.Account,
            withheld_ops: []
          }
        ]
      }

      expected = """
      # RESOLVE: the user entity designation is moving from MyApp.User to MyApp.Account - role grants reference MyApp.User rows, so they cannot follow it.
      # Write both ops, then delete the resolve! line. API:
      #   delete_role_grants()                   - every grant in the store is deleted
      #   designate_user_entity MyApp.Account    - the store's references follow it
      resolve! :user_entity, from: MyApp.User, to: MyApp.Account
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders a removed designation question as the store's drop" do
      plan = %{
        ops: [],
        questions: [%{kind: :user_entity, from: MyApp.User, to: nil, withheld_ops: []}]
      }

      rendered = render(plan, @module)

      assert rendered =~
               "designate_user_entity nil              - the role grant store is dropped"

      assert rendered =~ "resolve! :user_entity, from: MyApp.User, to: nil"
    end

    test "renders a fill question for a to-one, which takes no default" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:owner],
            members: [{:add_relationship, :owner, MyApp.User, []}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      rendered = render(plan, @module)

      assert rendered =~ "#   add_relationship :owner, MyApp.User, backfill: <id or expression>"
      assert rendered =~ "#   add_relationship :owner, MyApp.User, optional: true"
      refute rendered =~ "default:"
    end

    test "renders a tightening question with its answers" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:title],
            members: [{:change_attribute, :title, [optional: false]}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :title is required, and MyApp.Task already holds rows - they need a value.
        # Write the op with one of these, then delete the resolve! line. API:
        #   change_attribute :title, optional: false, backfill: <value or expression>  - the rows holding nil receive it, once, computed from each row when it names the row's fields
        #   change_attribute :title, optional: false, backfill: fn field -> <query words> end  - the same, in one update
        #   change_attribute :title, optional: false, backfill: fn field -> <Elixir> end  - the same, run row by row
        #   change_attribute :title, optional: false  - every row already holds a value - the apply refuses otherwise
        #   keep optional: true on :title in the entity type  - no op, the nils stay
        resolve! :fill, attributes: [:title]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "writes the relaxations of the blocks asking for a fill in blocks above all of them" do
      fill = fn entity, name ->
        %{
          kind: :fill,
          entity: entity,
          attributes: [name],
          members: [{:change_attribute, name, [optional: false]}],
          withheld_ops: [],
          freeing_ops: []
        }
      end

      plan = %{
        ops: [
          %{op: :add_attribute, entity: MyApp.Beta, name: :note, type: :string, opts: []},
          %{op: :change_relationship, entity: MyApp.Beta, name: :a, changes: [optional: true]}
        ],
        questions: [fill.(MyApp.Alpha, :title), fill.(MyApp.Beta, :rank)]
      }

      [before_questions, alpha_question, beta_question] =
        plan
        |> render(@module)
        |> String.split("# RESOLVE:")

      assert before_questions =~
               "change_entity MyApp.Beta do\n    change_relationship :a, optional: true\n  end\n\n" <>
                 "  change_entity MyApp.Alpha do"

      refute alpha_question =~ "change_relationship :a"
      assert beta_question =~ "add_attribute :note, :string"
      refute beta_question =~ "change_relationship :a"
    end

    test "writes the changes making a to-one optional above the blocks asking for a fill" do
      fill = fn entity, name ->
        %{
          kind: :fill,
          entity: entity,
          attributes: [name],
          members: [{:change_attribute, name, [optional: false]}],
          withheld_ops: [],
          freeing_ops: []
        }
      end

      change = fn name, changes ->
        %{op: :change_relationship, entity: MyApp.Beta, name: name, changes: changes}
      end

      plan = %{
        ops: [
          change.(:a, optional: true, unique: true),
          change.(:c, optional: true, type: MyApp.Gamma),
          change.(:g, type: MyApp.Gamma),
          change.(:d, type: [MyApp.Alpha]),
          change.(:e, unique: true),
          %{op: :delete_relationship, entity: MyApp.Beta, name: :f}
        ],
        questions: [fill.(MyApp.Alpha, :title), fill.(MyApp.Beta, :rank)]
      }

      [before_questions, _alpha_question, beta_question] =
        plan
        |> render(@module)
        |> String.split("# RESOLVE:")

      assert before_questions =~
               "change_entity MyApp.Beta do\n" <>
                 "    change_relationship :a, optional: true, unique: true\n" <>
                 "  end\n\n" <>
                 "  change_entity MyApp.Alpha do"

      # A retarget can add a required edge, and it, optional or not, a to-many and a delete change
      # what Beta's own backfill can still read. The cycle note lists them too, as comments.
      beta_lines = String.split(beta_question, "\n")

      for line <- [
            "change_relationship :c, optional: true, type: MyApp.Gamma",
            "change_relationship :d, type: [MyApp.Alpha]",
            "change_relationship :g, type: MyApp.Gamma",
            "change_relationship :e, unique: true",
            "delete_relationship :f"
          ] do
        assert ("    " <> line) in beta_lines
      end
    end

    test "notes the lines that can end a required to-one in the fill questions below another block's fill" do
      fill = fn entity, name ->
        %{
          kind: :fill,
          entity: entity,
          attributes: [name],
          members: [{:change_attribute, name, [optional: false]}],
          withheld_ops: [],
          freeing_ops: []
        }
      end

      plan = %{
        ops: [
          %{op: :delete_relationship, entity: MyApp.Alpha, name: :z},
          %{op: :delete_relationship, entity: MyApp.Beta, name: :a},
          %{
            op: :change_relationship,
            entity: MyApp.Beta,
            name: :d,
            changes: [type: [MyApp.Alpha]]
          },
          %{op: :change_relationship, entity: MyApp.Beta, name: :e, changes: [unique: true]},
          %{op: :change_relationship, entity: MyApp.Beta, name: :g, changes: [type: MyApp.Gamma]},
          %{op: :delete_attribute, entity: MyApp.Beta, name: :note}
        ],
        questions: [
          fill.(MyApp.Alpha, :title),
          fill.(MyApp.Beta, :rank),
          %{
            kind: :relationships,
            entity: MyApp.Beta,
            deleted: [:owner],
            added: [:author],
            hints: [],
            withheld_ops: []
          }
        ]
      }

      [_before_questions, alpha_question, _rename_question, beta_question] =
        plan
        |> render(@module)
        |> String.split("# RESOLVE:")

      refute alpha_question =~ "If one of these"

      assert beta_question =~
               "    # If one of these ends a cycle of required to-ones that a line above closes, " <>
                 "write it in a change_entity block of its own above that line, with the " <>
                 "delete_unique lines naming it - unless this block's backfill reads what it " <>
                 "takes away:\n" <>
                 "    #   delete_relationship :a\n" <>
                 "    #   change_relationship :d, type: [MyApp.Alpha]\n" <>
                 "    #   change_relationship :g, type: MyApp.Gamma\n" <>
                 "    #   your answer to the relationships question\n" <>
                 "    resolve! :fill, attributes: [:rank]\n"
    end

    # Gamma's block asks no fill, so it's written above Alpha's, the first block asking one.
    for {label, gamma_ops, gamma_questions, noted?} <- [
          {"a retarget", [%{op: :change_relationship, name: :g, changes: [type: MyApp.Alpha]}],
           [], true},
          {"a relationships question adding a required to-one", [],
           [
             %{
               kind: :relationships,
               deleted: [:old],
               added: [:g],
               hints: [],
               withheld_ops: [
                 %{op: :add_relationship, name: :g, type: MyApp.Alpha, opts: []},
                 %{op: :delete_relationship, name: :old}
               ]
             }
           ], true},
          {"an optional retarget",
           [%{op: :change_relationship, name: :g, changes: [optional: true, type: MyApp.Alpha]}],
           [], false},
          {"an optional to-one",
           [%{op: :add_relationship, name: :g, type: MyApp.Alpha, opts: [optional: true]}], [],
           false},
          {"a to-many", [%{op: :add_relationship, name: :g, type: [MyApp.Alpha], opts: []}], [],
           false},
          {"a created entity type's required to-one",
           [
             %{op: :create_entity},
             %{op: :add_relationship, name: :g, type: MyApp.Alpha, opts: []}
           ], [], false}
        ] do
      test "#{if noted?, do: "notes", else: "doesn't note"} the lines that can end a required to-one in the first fill question below #{label}" do
        in_gamma = fn item ->
          item
          |> Map.put(:entity, MyApp.Gamma)
          |> Map.update(:withheld_ops, [], fn ops ->
            Enum.map(ops, &Map.put(&1, :entity, MyApp.Gamma))
          end)
        end

        plan = %{
          ops: [
            %{op: :delete_relationship, entity: MyApp.Alpha, name: :e}
            | Enum.map(unquote(Macro.escape(gamma_ops)), in_gamma)
          ],
          questions: [
            %{
              kind: :fill,
              entity: MyApp.Alpha,
              attributes: [:title],
              members: [{:change_attribute, :title, [optional: false]}],
              withheld_ops: [],
              freeing_ops: []
            }
            | Enum.map(unquote(Macro.escape(gamma_questions)), in_gamma)
          ]
        }

        assert render(plan, @module) =~ "#   delete_relationship :e\n" == unquote(noted?)
      end
    end

    # An answer can take away a member whose column a fill takes, so the fills come below it.
    test "writes the fills last, with the ops freeing a column one takes above them" do
      to_many = %{
        op: :change_relationship,
        entity: MyApp.Beta,
        name: :place,
        changes: [type: [MyApp.Alpha]]
      }

      fill = %{kind: :fill, withheld_ops: [], freeing_ops: []}

      plan = %{
        ops: [%{op: :delete_attribute, entity: MyApp.Beta, name: :note}, to_many],
        questions: [
          Map.merge(fill, %{
            entity: MyApp.Alpha,
            attributes: [:title],
            members: [{:change_attribute, :title, [optional: false]}]
          }),
          Map.merge(fill, %{
            entity: MyApp.Beta,
            attributes: [:place_id],
            members: [{:add_attribute, :place_id, :uuid, []}],
            freeing_ops: [to_many]
          }),
          %{
            kind: :relationships,
            entity: MyApp.Beta,
            deleted: [:foo],
            added: [:bar],
            hints: [],
            withheld_ops: [%{op: :delete_unique, entity: MyApp.Beta, fields: [:foo, :place]}]
          },
          Map.merge(fill, %{
            entity: MyApp.Beta,
            attributes: [:rank],
            members: [{:change_attribute, :rank, [optional: false]}],
            freeing_ops: [to_many]
          })
        ]
      }

      [_alpha_block, beta_block] =
        plan
        |> render(@module)
        |> String.split("change_entity MyApp.Beta do\n")

      [_header, rename_question, place_question, rank_question] =
        String.split(beta_block, "# RESOLVE:")

      # The to-many change still takes :place from under the key the answer can respell.
      assert rename_question =~ "the ops below take :place from it"

      assert [_question, "\n    change_relationship :place, type: [MyApp.Alpha]\n    "] =
               String.split(rename_question, ~r/resolve! :relationships, .*/)

      notes =
        "    # The lines above free a column a fill in this block takes. To fill from what one " <>
          "of them takes away, rename that member there instead, fill from the new name, then " <>
          "write the line below for the new name, renaming the member back after it if it " <>
          "stays:\n" <>
          "    #   change_relationship :place, type: [MyApp.Alpha]\n" <>
          "    # The answers above come first, since one can free a column a fill takes - one " <>
          "taking away what a backfill reads renames the member there and takes it away below, " <>
          "or goes below the fills when it frees no column a fill takes.\n"

      assert place_question =~ notes
      assert rank_question =~ notes

      # Above the fills it can still end a cycle a line in an earlier block closes.
      assert place_question =~
               ~r/ends a cycle of required to-ones.*\n    #   change_relationship :place, type: /

      assert rank_question =~
               "resolve! :fill, attributes: [:rank]\n    delete_attribute :note\n  end\nend"
    end

    # A roles answer frees no column.
    for {label, other_questions} <- [
          {"nothing else", []},
          {"only roles",
           [
             %{
               kind: :roles,
               entity: MyApp.Task,
               deleted: [MyApp.Roles.Legacy],
               added: [MyApp.Roles.Maintainer],
               hints: [],
               withheld_ops: []
             }
           ]}
        ] do
      test "notes no answers above a fill whose block asks #{label} besides" do
        fill = %{
          kind: :fill,
          entity: MyApp.Task,
          attributes: [:rank],
          members: [{:change_attribute, :rank, [optional: false]}],
          withheld_ops: [],
          freeing_ops: []
        }

        plan = %{ops: [], questions: [fill | unquote(Macro.escape(other_questions))]}

        refute render(plan, @module) =~ "The answers above"
      end
    end

    test "writes a tightening beside a type change as two ops when it backfills" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:rank],
            members: [{:change_attribute, :rank, [optional: false, type: :string]}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      rendered = render(plan, @module)

      assert rendered =~
               "#   change_attribute :rank, type: :string  - first, as an op of its own"

      assert rendered =~ "#   change_attribute :rank, optional: false, backfill: <value or"

      assert rendered =~
               "#   change_attribute :rank, optional: false, type: :string  - every row already"
    end

    test "keeps the other changes in the answer leaving the member optional" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:rank],
            members: [{:change_attribute, :rank, [max: 10, optional: false]}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      assert render(plan, @module) =~
               "#   change_attribute :rank, max: 10  - keep optional: true on :rank in the " <>
                 "entity type, the nils stay"
    end

    test "writes a block creating an entity type above the others" do
      plan = %{
        ops: [
          %{
            op: :add_relationship,
            entity: MyApp.Alpha,
            name: :zed,
            type: MyApp.Zed,
            opts: [optional: true]
          },
          %{op: :create_entity, entity: MyApp.Zed}
        ],
        questions: []
      }

      rendered = render(plan, @module)

      {create_at, _length} = :binary.match(rendered, "create_entity MyApp.Zed")
      {change_at, _length} = :binary.match(rendered, "change_entity MyApp.Alpha")

      assert create_at < change_at
    end

    test "renders a fill question with its answers" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:title],
            members: [{:add_attribute, :title, :string, []}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :title is required, and MyApp.Task already holds rows - they need a value.
        # Write the op with one of these, then delete the resolve! line. API:
        #   add_attribute :title, :string, backfill: <value or expression>  - existing rows receive it, once, computed from each row when it names the row's fields
        #   add_attribute :title, :string, backfill: fn field -> <query words> end  - the same, in one update
        #   add_attribute :title, :string, backfill: fn field -> <Elixir> end  - the same, run row by row
        #   add_attribute :title, :string, default: <value>  - existing rows receive it, and so does every row created without one from now on
        #   add_attribute :title, :string, optional: true  - existing rows stay empty
        resolve! :fill, attributes: [:title]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "leaves the default answer out of a fill question for a unique attribute" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:slug],
            members: [{:add_attribute, :slug, :string, [unique: true]}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :slug is required, and MyApp.Task already holds rows - they need a value.
        # Write the op with one of these, then delete the resolve! line. API:
        #   add_attribute :slug, :string, unique: true, backfill: <value or expression>  - existing rows receive it, once, computed from each row when it names the row's fields
        #   add_attribute :slug, :string, unique: true, backfill: fn field -> <query words> end  - the same, in one update
        #   add_attribute :slug, :string, unique: true, backfill: fn field -> <Elixir> end  - the same, run row by row
        #   add_attribute :slug, :string, unique: true, optional: true  - existing rows stay empty
        resolve! :fill, attributes: [:slug]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders every entity-scoped op kind" do
      plan = %{
        ops: [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :estimate,
            changes: [default: nil, type: :float]
          },
          %{op: :delete_attribute, entity: MyApp.Task, name: :legacy},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :tags,
            type: [MyApp.Tag],
            opts: [optional: true]
          },
          %{
            op: :change_relationship,
            entity: MyApp.Task,
            name: :author,
            changes: [type: MyApp.Account]
          },
          %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator},
          %{op: :delete_relationship, entity: MyApp.Task, name: :project},
          %{op: :add_role, entity: MyApp.Task, name: :owner, opts: [extends: :editor]},
          %{op: :change_role, entity: MyApp.Task, name: :editor, changes: [granted_to: :creator]},
          %{op: :rename_role, entity: MyApp.Task, from: :moderator, to: :maintainer},
          %{op: :delete_role, entity: MyApp.Task, name: :viewer},
          %{op: :add_unique, entity: MyApp.Task, fields: [:workspace, :slug]},
          %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
          %{
            op: :add_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            value: :doing,
            opts: [after: :todo]
          },
          %{
            op: :rename_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            from: :done,
            to: :completed
          },
          %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :draft},
          %{
            op: :reorder_enum_values,
            entity: MyApp.Task,
            attribute: :status,
            values: [:todo, :doing, :completed]
          }
        ],
        questions: []
      }

      expected = """
      change_entity MyApp.Task do
        delete_unique [:kind, :slug]
        change_attribute :estimate, default: nil, type: :float
        delete_attribute :legacy
        add_relationship :tags, [MyApp.Tag], optional: true
        change_relationship :author, type: MyApp.Account
        rename_relationship :author, :creator
        delete_relationship :project
        add_role :owner, extends: :editor
        change_role :editor, granted_to: :creator
        rename_role :moderator, :maintainer
        delete_role :viewer
        add_unique [:workspace, :slug]
        add_enum_value :status, :doing, after: :todo
        rename_enum_value :status, :done, :completed
        delete_enum_value :status, :draft
        # The declared order of :status changed - queries ordering by it sort rows differently now.
        # No value changes: every row keeps what it holds, and the column is rebuilt to apply the order.
        reorder_enum_values :status, [:todo, :doing, :completed]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    # A reorder reads as a refactor and is not one - the declared order is what ordering by the
    # attribute follows - so the draft says what changed, and what did not.
    test "warns above a reorder, saying no value changes" do
      plan = %{
        ops: [
          %{
            op: :reorder_enum_values,
            entity: MyApp.Task,
            attribute: :priority,
            values: [:high, :low, :medium]
          }
        ],
        questions: []
      }

      expected = """
      change_entity MyApp.Task do
        # The declared order of :priority changed - queries ordering by it sort rows differently now.
        # No value changes: every row keeps what it holds, and the column is rebuilt to apply the order.
        reorder_enum_values :priority, [:high, :low, :medium]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders global role ops as flat statements" do
      plan = %{
        ops: [
          %{op: :add_role, role: MyApp.Roles.Support, opts: [extends: [MyApp.Roles.Admin]]},
          %{op: :change_role, role: MyApp.Roles.Owner, changes: [extends: nil]},
          %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Manager},
          %{op: :delete_role, role: MyApp.Roles.Legacy}
        ],
        questions: []
      }

      expected = """
      add_role MyApp.Roles.Support, extends: [MyApp.Roles.Admin]

      change_role MyApp.Roles.Owner, extends: nil

      rename_role MyApp.Roles.Admin, MyApp.Roles.Manager

      delete_role MyApp.Roles.Legacy
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders an entity-scoped question inside its block, before the ops" do
      plan = %{
        ops: [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [backfill: 0]
          }
        ],
        questions: [
          %{
            kind: :attributes,
            entity: MyApp.Task,
            deleted: [:desc, :name],
            added: [:body, :title],
            hints: [{:rename, :name, :title}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :desc, :name disappeared from the attributes - :body, :title appeared.
        # Write the ops that express what happened, then delete the resolve! line. API:
        #   rename_attribute :old, :new             - the column is renamed, its data kept
        #   delete_attribute :name                  - the column and its data are dropped
        #   add_attribute :name, :type, opts        - a new column, empty for existing rows
        # Looks likely: rename_attribute :name, :title
        resolve! :attributes, deleted: [:desc, :name], added: [:body, :title]
        add_attribute :priority, :integer, backfill: 0
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "says what each answer does to the keys withheld with the question" do
      plan = %{
        ops: [%{op: :add_unique, entity: MyApp.Task, fields: [:slug, :title]}],
        questions: [
          %{
            kind: :attributes,
            entity: MyApp.Task,
            deleted: [:name],
            added: [:title],
            hints: [{:rename, :name, :title}],
            withheld_ops: [
              %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :name]},
              %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: []},
              %{op: :delete_attribute, entity: MyApp.Task, name: :name},
              %{op: :add_unique, entity: MyApp.Task, fields: [:kind, :title]}
            ]
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :name disappeared from the attributes - :title appeared.
        # Write the ops that express what happened, then delete the resolve! line. API:
        #   rename_attribute :old, :new             - the column is renamed, its data kept
        #   delete_attribute :name                  - the column and its data are dropped
        #   add_attribute :name, :type, opts        - a new column, empty for existing rows
        # Looks likely: rename_attribute :name, :title
        # Key [:kind, :name] names what disappeared - a rename carries it along, a delete needs delete_unique [:kind, :name] first
        # Key [:kind, :title] names what appeared - the next generated file adds it if the answer leaves it out
        resolve! :attributes, deleted: [:name], added: [:title]
        add_unique [:slug, :title]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "warns when the ops below a question take a field from a key withheld with it" do
      plan = %{
        ops: [
          %{op: :delete_relationship, entity: MyApp.Task, name: :workspace},
          %{
            op: :change_relationship,
            entity: MyApp.Task,
            name: :owner,
            changes: [type: [MyApp.User]]
          },
          %{
            op: :change_relationship,
            entity: MyApp.Task,
            name: :team,
            changes: [type: MyApp.Group]
          },
          %{op: :delete_attribute, entity: MyApp.Task, name: :legacy}
        ],
        questions: [
          %{
            kind: :attributes,
            entity: MyApp.Task,
            deleted: [:slug],
            added: [:handle],
            hints: [],
            withheld_ops: [
              %{
                op: :delete_unique,
                entity: MyApp.Task,
                fields: [:workspace, :owner, :team, :slug]
              }
            ]
          }
        ]
      }

      rendered = render(plan, @module)

      assert rendered =~
               "# Key [:workspace, :owner, :team, :slug] names what disappeared - a rename carries it along, a delete needs delete_unique [:workspace, :owner, :team, :slug] first - the ops below take :workspace, :owner from it, so a rename leaves the key needing a delete_unique of its own\n"
    end

    # The answer to the fill question brings an attribute under the name the relationship
    # still holds, and the replay refuses that while a key names it.
    test "renders the keys that leave above the questions of their block" do
      plan = %{
        ops: [
          %{op: :delete_unique, entity: MyApp.Task, fields: [:owner, :slug]},
          %{op: :delete_relationship, entity: MyApp.Task, name: :owner},
          %{op: :add_unique, entity: MyApp.Task, fields: [:owner, :slug]}
        ],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:owner],
            members: [{:add_attribute, :owner, :string, []}],
            withheld_ops: [],
            freeing_ops: []
          }
        ]
      }

      module = written_module(random_module())
      rendered = render(plan, module)

      lines =
        rendered
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      block_start = Enum.find_index(lines, &(&1 == "change_entity MyApp.Task do"))

      assert [
               "change_entity MyApp.Task do",
               "delete_unique [:owner, :slug]",
               "# RESOLVE: :owner is required" <> _rest | _lines
             ] = Enum.drop(lines, block_start)

      assert Enum.take(lines, -5) == [
               "resolve! :fill, attributes: [:owner]",
               "delete_relationship :owner",
               "add_unique [:owner, :slug]",
               "end",
               "end"
             ]

      answered =
        String.replace(
          rendered,
          "resolve! :fill, attributes: [:owner]",
          ~s(add_attribute :owner, :string, backfill: "x")
        )

      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:owner, :slug]]
          }
        })

      Code.compile_string(answered, "app/migrations/20260813091522.ex")

      ops = module.__hologram_migration__().ops

      assert Model.fold(replayed, ops).entities[MyApp.Task] == %{
               attributes: [{:owner, :string, []}, {:slug, :string, []}],
               relationships: [],
               roles: [],
               uniques: [[:owner, :slug]]
             }
    end

    test "renders an entity question at the top level" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :entities,
            deleted: [MyApp.Draft],
            added: [MyApp.Sketch],
            hints: [{:rename, MyApp.Draft, MyApp.Sketch}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      # RESOLVE: MyApp.Draft disappeared from the entity types - MyApp.Sketch appeared.
      # Write the ops that express what happened, then delete the resolve! line. API:
      #   rename_entity MyApp.Old, MyApp.New      - the table is renamed, its rows kept
      #   delete_entity MyApp.Old                 - the table and its rows are dropped
      #   create_entity MyApp.New do ... end      - a new table
      # Looks likely: rename_entity MyApp.Draft, MyApp.Sketch
      resolve! :entities, deleted: [MyApp.Draft], added: [MyApp.Sketch]
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "names the attribute in an enum value question" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :enum_values,
            entity: MyApp.Task,
            attribute: :status,
            deleted: [:done],
            added: [:completed],
            hints: [{:rename, :done, :completed}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      change_entity MyApp.Task do
        # RESOLVE: :done disappeared from the values of :status - :completed appeared.
        # Write the ops that express what happened, then delete the resolve! line. API:
        #   rename_enum_value :attr, :old, :new     - the rows holding it follow the label
        #   delete_enum_value :attr, :value         - refused while rows still hold it
        #   add_enum_value :attr, :value, opts      - before:/after: place it in the order
        # Looks likely: rename_enum_value :status, :done, :completed
        resolve! :enum_values, attribute: :status, deleted: [:done], added: [:completed]
      end
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders a question without hints" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :roles,
            deleted: [MyApp.Roles.Moderator, MyApp.Roles.Legacy],
            added: [MyApp.Roles.Maintainer],
            hints: [],
            withheld_ops: []
          }
        ]
      }

      expected = """
      # RESOLVE: MyApp.Roles.Moderator, MyApp.Roles.Legacy disappeared from the roles - MyApp.Roles.Maintainer appeared.
      # Write the ops that express what happened, then delete the resolve! line. API:
      #   rename_role :old, :new                  - existing grants follow the label
      #   delete_role :name                       - the grants of that role die with it
      #   add_role :name, opts                    - a new grantable role
      resolve! :roles,
        deleted: [MyApp.Roles.Moderator, MyApp.Roles.Legacy],
        added: [MyApp.Roles.Maintainer]
      """

      assert render(plan, @module) == module_text(@module, expected)
    end

    test "renders text the loader reads back as the given ops" do
      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch},
        %{op: :create_entity, entity: MyApp.Comment},
        %{op: :add_attribute, entity: MyApp.Comment, name: :body, type: :string, opts: []},
        %{op: :add_attribute, entity: MyApp.Comment, name: :kind, type: :string, opts: []},
        %{op: :add_unique, entity: MyApp.Comment, fields: [:kind, :body]},
        %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :doing,
          opts: [after: :todo]
        },
        %{op: :add_role, role: MyApp.Roles.Support, opts: []},
        %{op: :change_role, role: MyApp.Roles.Support, changes: [extends: [MyApp.Roles.Staff]]},
        %{op: :delete_role_grants},
        %{op: :designate_user_entity, entity: MyApp.Comment}
      ]

      loaded = compile_rendered(%{ops: ops, questions: []})

      assert Enum.map(loaded, &Map.delete(&1, :line)) == ops
    end

    test "renders a draft the loader reads back with its resolve! op" do
      question = %{
        kind: :attributes,
        entity: MyApp.Task,
        deleted: [:name],
        added: [:title],
        hints: [{:rename, :name, :title}],
        withheld_ops: []
      }

      loaded = compile_rendered(%{ops: [], questions: [question]})

      assert Enum.map(loaded, &Map.delete(&1, :line)) == [
               %{
                 op: :resolve!,
                 entity: MyApp.Task,
                 kind: :attributes,
                 payload: [deleted: [:name], added: [:title]]
               }
             ]

      assert Loader.unresolved(loaded) == loaded
    end
  end
end
