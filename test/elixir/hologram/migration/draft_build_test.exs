defmodule Hologram.Migration.DraftBuildTest do
  # async: false - the build env is Mix's, one for the whole VM, and these tests change it.
  use Hologram.Test.BasicCase, async: false

  alias Hologram.Migration.Loader

  @draft_body "resolve! :entities, deleted: [MyApp.Gone], added: [MyApp.Came]"

  setup do
    env = Mix.env()

    on_exit(fn -> Mix.env(env) end)
  end

  # Gives the module an application spec, so Hologram.Reflection lists it as a migration.
  defp load_app_with_module(app, module) do
    spec =
      {:application, app,
       applications: [:hologram],
       description: ~c"fixture",
       modules: [module],
       registered: [],
       vsn: ~c"0.0.0"}

    :ok = :application.load(spec)

    on_exit(fn -> :application.unload(app) end)
  end

  test "refuses a draft in a prod build" do
    Mix.env(:prod)

    expected_msg =
      normalize_newlines("""
      the migration draft is not resolved yet, and a prod build refuses it:
        app/migrations/20260813091522.ex:4 - :entities
      Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
      """)

    assert_error Hologram.CompileError, expected_msg, fn ->
      compile_migration("20260813091522", @draft_body)
    end
  end

  test "refuses a draft whose resolve! line sits in an entity block, in any build but dev and test" do
    Mix.env(:staging)

    body = """
    change_entity MyApp.Task do
      resolve! :fill, attributes: [:title]
    end
    """

    expected_msg =
      normalize_newlines("""
      the migration draft is not resolved yet, and a staging build refuses it:
        app/migrations/20260813091522.ex:5 - :fill
      Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
      """)

    assert_error Hologram.CompileError, expected_msg, fn ->
      compile_migration("20260813091522", body)
    end
  end

  test "compiles a draft in a dev build" do
    Mix.env(:dev)

    module = compile_migration("20260813091522", @draft_body)

    assert [%{op: :resolve!}] = module.__hologram_migration__().ops
  end

  test "compiles a draft in a test build" do
    Mix.env(:test)

    module = compile_migration("20260813091522", @draft_body)

    assert [%{op: :resolve!}] = module.__hologram_migration__().ops
  end

  test "compiles a resolved migration in a prod build" do
    Mix.env(:prod)

    module = compile_migration("20260813091522", "create_entity MyApp.Task")

    assert [%{op: :create_entity}] = module.__hologram_migration__().ops
  end

  test "refuses a draft compiled in a dev build in a prod build that reuses its beam" do
    Mix.env(:dev)

    module = compile_migration("20260813091522", @draft_body)

    load_app_with_module(:hologram_draft_build_reused_beam_fixture_app, module)

    expected_msg =
      normalize_newlines("""
      the migration draft is not resolved yet, and a prod build refuses it:
        app/migrations/20260813091522.ex:4 - :entities
      Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
      """)

    assert_error Hologram.CompileError, expected_msg, fn ->
      Loader.validate_project_resolved!(:prod)
    end
  end

  test "accepts a draft compiled in a dev build in a dev build that reuses its beam" do
    Mix.env(:dev)

    module = compile_migration("20260813091522", @draft_body)

    load_app_with_module(:hologram_draft_build_dev_beam_fixture_app, module)

    assert Loader.validate_project_resolved!(:dev) == :ok
  end
end
