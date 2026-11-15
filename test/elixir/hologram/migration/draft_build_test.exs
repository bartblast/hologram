defmodule Hologram.Migration.DraftBuildTest do
  # async: false - the build env is Mix's, one for the whole VM, and these tests change it.
  use Hologram.Test.BasicCase, async: false

  @draft_body "resolve! :entities, deleted: [MyApp.Gone], added: [MyApp.Came]"

  setup do
    env = Mix.env()

    on_exit(fn -> Mix.env(env) end)
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
end
