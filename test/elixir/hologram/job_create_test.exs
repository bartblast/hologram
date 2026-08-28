defmodule Hologram.JobCreateTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Job, only: [create: 1, create: 2, create: 3, create!: 1, create!: 2, create!: 3]
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.DB
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module2
  alias Hologram.Test.Fixtures.Job.Module3

  # Built at run time rather than written as a literal: the clauses of the option parser make a
  # literal the type checker refuses at the call site, which is the point of them - what these two
  # tests exercise is the raise that answers options a program computed. Mapped over a list rather
  # than taken from a map, because a map's atom keys come out in the order the atoms were created,
  # which differs between runs.
  defp computed_opts(opts) do
    Enum.map(opts, & &1)
  end

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  describe "create/3" do
    test "writes the job queued" do
      assert {:ok, job} = create(Module1)

      assert job.status == :queued
      assert job.error == nil
      assert DB.read(Module1, job.id).status == :queued
    end

    test "applies the given values" do
      assert {:ok, job} = create(Module3, outcome: :ok)

      assert job.outcome == :ok
      assert DB.read(Module3, job.id).outcome == :ok
    end

    test "stamps the acting user" do
      user = create_user("enqueuer@example.com")

      assert {:ok, job} = as_user(user, fn -> create(Module1) end)
      assert job.actor_id == user.id
    end

    test "stamps no actor without an acting user" do
      assert {:ok, job} = create(Module1)
      assert job.actor_id == nil
    end

    test "evaluates the write as create for the acting user" do
      user = create_user("claimer@example.com")

      expected_msg = ~r/^not allowed to archive Hologram.Test.Fixtures.Job.Module1 "/

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(Module1, %{}, authorize: :archive) end)
      end

      assert DB.read(Module1) == []
    end

    test "claims the server's authority with the trust option" do
      user = create_user("truster@example.com")

      assert {:ok, job} = as_user(user, fn -> create(Module2, %{}, trust: true) end)
      assert job.actor_id == user.id
      assert DB.read(Module2, job.id) != nil
    end

    test "creates a job type that declares no allow lines without an acting user" do
      assert {:ok, job} = create(Module2)
      assert DB.read(Module2, job.id) != nil
    end

    test "raises on a module that is not a job type" do
      expected_msg =
        "Hologram.Test.Fixtures.Entity.Module14 is not a job type - Job.create takes a module defined with use Hologram.Job"

      assert_error ArgumentError, expected_msg, fn -> create(Module14) end
    end

    test "raises on a value of an attribute the framework sets" do
      expected_msg =
        ":status of Hologram.Test.Fixtures.Job.Module1 is set by the framework - a job is enqueued as queued, and the worker records the rest"

      assert_error ArgumentError, expected_msg, fn -> create(Module1, status: :done) end
    end

    test "raises on an unknown option" do
      expected_msg = "Job.create takes authorize: operation or trust: true, got: [retry: true]"

      assert_error ArgumentError, expected_msg, fn ->
        create(Module1, %{}, computed_opts(retry: true))
      end
    end

    test "raises on claiming both authorities" do
      expected_msg =
        "Job.create takes authorize: operation or trust: true, got: [authorize: :archive, trust: true]"

      assert_error ArgumentError, expected_msg, fn ->
        create(Module1, %{}, computed_opts(authorize: :archive, trust: true))
      end
    end

    test "returns the violations of a value the declarations refuse" do
      assert create(Module3, %{}) == {:error, %{outcome: [:required]}}

      assert DB.read(Module3) == []
    end

    test "raises on a job type that declares no allow lines under an acting user" do
      user = create_user("blocked@example.com")

      expected_msg =
        "cannot create Hologram.Test.Fixtures.Job.Module2 as a user - it declares no allow lines, so no rule can grant the create. Add \"allow :create, ...\" to enqueue it from an action, or create it from server code, where there is no acting user."

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(Module2) end)
      end

      assert DB.read(Module2) == []
    end
  end

  describe "create!/3" do
    test "returns the written job" do
      job = create!(Module1)

      assert job.status == :queued
      assert DB.read(Module1, job.id) != nil
    end

    test "raises on a value the declarations refuse" do
      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Job.Module3:
          * attribute :outcome is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn -> create!(Module3, %{}) end
    end

    test "raises on a denial" do
      user = create_user("banged@example.com")

      expected_msg = ~r/^not allowed to archive Hologram.Test.Fixtures.Job.Module1 "/

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create!(Module1, %{}, authorize: :archive) end)
      end
    end
  end
end
