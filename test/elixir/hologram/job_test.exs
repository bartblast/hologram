defmodule Hologram.JobTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Job

  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module2
  alias Hologram.Test.Fixtures.Job.Module3

  describe "__using__/1" do
    test "marks the module as a job type" do
      assert Module1.__is_hologram_job__() == true
    end

    test "marks the module as an entity type" do
      assert Module1.__is_hologram_entity__() == true
    end

    test "declares the attributes the framework owns" do
      assert Module1.__attributes__() == [
               {:actor_id, :uuid, [optional: true]},
               {:attempt, :integer, [default: 0]},
               {:error, :string, [optional: true, server_only: true]},
               {:run_as_server, :boolean, [default: false]},
               {:scheduled_at, :datetime, [optional: true]},
               {:status, :enum, [values: [:queued, :running, :done, :failed], default: :queued]}
             ]

      assert Module1.__relationships__() == []
    end

    test "builds a job queued, with nothing recorded of a run" do
      job = Module1.new()

      assert job.status == :queued
      assert job.actor_id == nil
      assert job.error == nil
    end

    test "raises when a framework attribute is redeclared" do
      expected_msg =
        "duplicate name :status used for attribute in Hologram.Test.Fixtures.Job.RedeclaringJob - attribute, relationship and derived field names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Job.RedeclaringJob do
          use Hologram.Job

          attribute :status, :string

          @impl Hologram.Job
          def run(_job), do: :ok
        end
        """)
      end
    end

    test "raises when the module defines no run/1" do
      expected_msg =
        "Hologram.Test.Fixtures.Job.RunlessJob uses Hologram.Job but defines no run/1 - run/1 is the work a job does, run after its row commits"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Job.RunlessJob do
          use Hologram.Job
        end
        """)
      end
    end

    test "raises when an unknown option is given" do
      expected_msg =
        "unknown option :user for use Hologram.Job in Hologram.Test.Fixtures.Job.UserOptJob - use Hologram.Job takes only :max_attempts, :max_concurrency and :timeout"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Job.UserOptJob do
          use Hologram.Job, user: true

          @impl Hologram.Job
          def run(_job), do: :ok
        end
        """)
      end
    end

    for option <- [:max_attempts, :max_concurrency],
        {label, value} <- [
          {"zero", "0"},
          {"a negative integer", "-1"},
          {"a float", "2.0"},
          {"a string", ~s("2")},
          {"a module attribute", "@limit"}
        ] do
      test "raises when #{option} is #{label}" do
        expected_msg =
          "invalid #{unquote(option)} #{unquote(value)} for use Hologram.Job in Hologram.Test.Fixtures.Job.BadLimitJob - it must be a positive integer, written as a literal"

        assert_error Hologram.CompileError, expected_msg, fn ->
          Code.eval_string("""
          defmodule Hologram.Test.Fixtures.Job.BadLimitJob do
            @limit 2

            use Hologram.Job, #{unquote(option)}: #{unquote(value)}

            @impl Hologram.Job
            def run(_job), do: :ok
          end
          """)
        end
      end
    end

    for {label, value} <- [
          {"zero", "0"},
          {"a negative integer", "-1"},
          {"a float", "2.0"},
          {"a string", ~s("2")},
          {"a module attribute", "@limit"},
          {"past the longest limit", "4_294_967_296"}
        ] do
      test "raises when timeout is #{label}" do
        expected_msg =
          "invalid timeout #{unquote(value)} for use Hologram.Job in Hologram.Test.Fixtures.Job.BadTimeoutJob - it must be a positive integer of milliseconds, at most 4294967295, written as a literal"

        assert_error Hologram.CompileError, expected_msg, fn ->
          Code.eval_string("""
          defmodule Hologram.Test.Fixtures.Job.BadTimeoutJob do
            @limit 2

            use Hologram.Job, timeout: #{unquote(value)}

            @impl Hologram.Job
            def run(_job), do: :ok
          end
          """)
        end
      end
    end

    test "takes the longest limit" do
      [{module, _binary}] =
        Code.compile_string("""
        defmodule Hologram.Test.Fixtures.Job.LongestTimeoutJob do
          use Hologram.Job, timeout: 4_294_967_295

          @impl Hologram.Job
          def run(_job), do: :ok
        end
        """)

      assert timeout(module) == 4_294_967_295
    end

    test "raises when the options are not a keyword list" do
      expected_msg =
        "invalid options :abc for use Hologram.Job in Hologram.Test.Fixtures.Job.NonKeywordOptsJob - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Job.NonKeywordOptsJob do
          use Hologram.Job, :abc

          @impl Hologram.Job
          def run(_job), do: :ok
        end
        """)
      end
    end
  end

  describe "max_attempts/1" do
    test "answers 10 for a job type that sets no limit" do
      assert max_attempts(Module3) == 10
    end

    test "answers the limit a job type's use line sets" do
      assert max_attempts(Module1) == 1
    end
  end

  describe "max_concurrency/1" do
    test "answers 10 for a job type that sets no limit" do
      assert max_concurrency(Module1) == 10
    end

    # The lowest limit there is, which tells a limit refused below 1 apart from one refused below 2.
    test "answers the limit a job type's use line sets" do
      assert max_concurrency(Module2) == 1
    end
  end

  describe "timeout/1" do
    test "answers an hour for a job type that sets no limit" do
      assert timeout(Module1) == 3_600_000
    end

    test "answers the limit a job type's use line sets" do
      assert timeout(Module2) == 5_000
    end
  end

  describe "framework_attribute_names/0" do
    test "names the attributes only the framework sets" do
      assert framework_attribute_names() ==
               [:actor_id, :attempt, :error, :run_as_server, :scheduled_at, :status]
    end
  end
end
