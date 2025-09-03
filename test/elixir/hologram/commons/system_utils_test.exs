defmodule Hologram.Commons.SystemUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.SystemUtils
  alias Hologram.Reflection

  describe "cmd_cross_platform/3" do
    setup do
      test_dir =
        Path.join([
          Reflection.tmp_dir(),
          "tests",
          "commons",
          "system_utils",
          "cmd_cross_platform_3"
        ])

      clean_dir(test_dir)

      [test_dir: test_dir]
    end

    test "executes a command by name from PATH" do
      {result, exit_status} = cmd_cross_platform("echo", ["hello"], [])

      assert exit_status == 0
      assert String.trim_trailing(result) == "hello"
    end

    test "executes a command with full path" do
      echo_path = System.find_executable("echo")
      {result, exit_status} = cmd_cross_platform(echo_path, ["world"], [])

      assert exit_status == 0
      assert String.trim_trailing(result) == "world"
    end

    test "returns non-zero exit status for failing commands" do
      {_result, exit_status} = cmd_cross_platform("false", [], [])

      assert exit_status != 0
    end

    test "raises when command not found in PATH" do
      assert_raise RuntimeError, ~r/executable not found in PATH/, fn ->
        cmd_cross_platform("nonexistentcommand123", [], [])
      end
    end

    test "raises when explicit path does not exist" do
      assert_raise RuntimeError, ~r/executable not found at/, fn ->
        cmd_cross_platform("/nonexistent/path/to/command", [], [])
      end
    end

    test "handles empty arguments list" do
      {result, exit_status} = cmd_cross_platform("echo", [], [])

      assert exit_status == 0
      assert String.trim_trailing(result) == ""
    end
  end

  describe "otp_version/0" do
    test "returns the OTP major version as integer" do
      assert to_string(otp_version()) == System.otp_release()
    end
  end
end
