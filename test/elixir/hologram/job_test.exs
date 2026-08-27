defmodule Hologram.JobTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Job.Module1

  describe "__using__/1" do
    test "marks the module as a job type" do
      assert Module1.__is_hologram_job__() == true
    end

    test "marks the module as an entity type" do
      assert Module1.__is_hologram_entity__() == true
    end

    test "declares nothing of its own" do
      assert Module1.__attributes__() == []
      assert Module1.__relationships__() == []
    end

    test "raises when the module defines no run/1" do
      expected_msg =
        "Hologram.Test.Fixtures.Job.RunlessJob uses Hologram.Job but defines no run/1 - run/1 is the work a job does, run once after its row commits"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Job.RunlessJob do
          use Hologram.Job
        end
        """)
      end
    end

    test "raises when an option is given" do
      expected_msg =
        "unknown option :user for use Hologram.Job in Hologram.Test.Fixtures.Job.UserOptJob - use Hologram.Job takes no options"

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
end
