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

    # Note: We use 'elixir --version' instead of 'echo' because on Windows,
    # echo.exe (from Git Bash/MSYS2) has flaky I/O buffering when executed via
    # full path, causing intermittent test failures where output is not captured.
    test "executes a command with full path" do
      command_path = System.find_executable("elixir")
      {result, exit_status} = cmd_cross_platform(command_path, ["--version"], [])

      assert exit_status == 0
      assert result =~ "Elixir"
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

  describe "os_process_alive?/1" do
    test "returns true for current process PID" do
      current_pid = String.to_integer(System.pid())
      assert os_process_alive?(current_pid)
    end

    test "returns false for non-existent PID" do
      # Use a very high PID that's unlikely to exist
      # Maximum PIDs vary by OS:
      # Linux = 32,768, see: https://stackoverflow.com/a/6294196/13040586
      # macOs = 99,998, see: https://apple.stackexchange.com/a/260798
      # Windows = 4,294,967,295, see: https://learn.microsoft.com/en-us/answers/questions/70930/maximum-value-of-process-id
      non_existent_pid = 32_768
      refute os_process_alive?(non_existent_pid)
    end

    test "handles PID 0 with platform-specific behavior" do
      # PID 0 has different behavior depending on the OS:
      # - Unix systems: scheduler/swapper, not a regular process (returns false)
      # - Windows: System Idle Process, visible to tasklist (returns true)
      windows? = match?({:win32, _name}, :os.type())

      case windows? do
        true ->
          # On Windows, PID 0 is System Idle Process and is visible to tasklist
          assert os_process_alive?(0)

        false ->
          # On Unix, PID 0 is kernel scheduler/swapper, not a regular process
          refute os_process_alive?(0)
      end
    end

    test "handles edge cases and invalid inputs gracefully" do
      # Negative PID (invalid)
      refute os_process_alive?(-1)

      # Test with 1 (usually init process on Unix, but the test is defensive)
      # This might be true on Unix systems, so we just verify it doesn't crash
      result = os_process_alive?(1)
      assert is_boolean(result)

      # Very large PID that's unlikely to exist (Windows max)
      refute os_process_alive?(4_294_967_295)
    end
  end

  describe "otp_version/0" do
    test "returns the OTP major version as integer" do
      assert to_string(otp_version()) == System.otp_release()
    end
  end
end
