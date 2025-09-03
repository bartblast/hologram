defmodule Hologram.Commons.SystemUtils do
  @moduledoc false

  alias Hologram.Commons.IntegerUtils

  @windows_exec_suffixes [".bat", ".cmd", ".exe"]

  @doc """
  Executes the given command cross-platform.

  Accepts either a bare command name (resolved via PATH) or an executable file path.
  On Windows, .cmd/.bat wrappers must be executed via "cmd /c".

  ## Parameters

    * `command_name_or_path` - Either a command name (e.g., "npm") or a full path to an executable
    * `args` - List of command arguments
    * `opts` - Options passed to System.cmd/3

  ## Returns

  A tuple `{result, exit_status}` as returned by `System.cmd/3`.

  ## Examples

      iex> SystemUtils.cmd_cross_platform("echo", ["hello"], [])
      {"hello\\n", 0}

      iex> SystemUtils.cmd_cross_platform("/usr/bin/echo", ["hello"], [])
      {"hello\\n", 0}

  """
  @spec cmd_cross_platform(String.t(), list(String.t()), keyword) ::
          {Collectable.t(), non_neg_integer()}
  # sobelow_skip ["CI.System"]
  # credo:disable-for-lines:11 Credo.Check.Design.DuplicatedCode
  def cmd_cross_platform(command_name_or_path, args, opts) do
    windows? = match?({:win32, _name}, :os.type())

    resolved_command_path = resolve_command_path!(command_name_or_path, windows?)

    if windows? and String.match?(resolved_command_path, ~r/\.(cmd|bat)$/i) do
      System.cmd("cmd", ["/c", resolved_command_path | args], opts)
    else
      System.cmd(resolved_command_path, args, opts)
    end
  end

  @doc """
  Checks if an OS process with the given PID is currently running.

  This function works cross-platform:
  - On Unix/Linux: Uses `ps -p <pid>`
  - On Windows: Uses `tasklist /FI "PID eq <pid>" /NH`

  ## Parameters

    * `os_pid` - The OS-level process ID to check

  ## Returns

  Returns `true` if the process is running, `false` otherwise.

  ## Examples

      iex> SystemUtils.os_process_alive?(System.pid())
      true

      iex> SystemUtils.os_process_alive?(32_768)
      false

  """
  @spec os_process_alive?(non_neg_integer()) :: boolean()
  def os_process_alive?(os_pid) do
    windows? = match?({:win32, _name}, :os.type())

    if windows? do
      os_process_alive_windows?(os_pid)
    else
      os_process_alive_unix?(os_pid)
    end
  rescue
    _error -> false
  catch
    _error -> false
  end

  @doc """
  Returns the OTP major version.
  """
  @spec otp_version :: integer
  def otp_version do
    IntegerUtils.parse!(System.otp_release())
  end

  defp find_windows_wrapper(explicit_command_path) do
    @windows_exec_suffixes
    |> Enum.map(&(explicit_command_path <> &1))
    |> Enum.find(&File.exists?/1)
  end

  defp has_windows_exec_ext?(path) do
    ext =
      path
      |> Path.extname()
      |> String.downcase()

    ext in @windows_exec_suffixes
  end

  defp os_process_alive_unix?(os_pid) do
    case cmd_cross_platform("ps", ["-p", to_string(os_pid)], []) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp os_process_alive_windows?(os_pid) do
    # Use tasklist with filter to check if PID exists
    # /FI "PID eq <pid>" filters for the specific process ID
    # /NH removes headers from output
    case cmd_cross_platform("tasklist", ["/FI", "PID eq #{os_pid}", "/NH"], []) do
      {output, 0} ->
        # If the process exists, tasklist will output a line with process info
        # If it doesn't exist, output will be empty or contain "No tasks are running..."
        output
        |> String.trim()
        |> String.contains?(to_string(os_pid))

      {_output, _status} ->
        false
    end
  end

  defp resolve_command_path!(command_name_or_path, windows?) do
    has_separator? = String.contains?(command_name_or_path, ["/", "\\"])

    if has_separator? do
      resolve_explicit_command_path!(command_name_or_path, windows?)
    else
      case System.find_executable(command_name_or_path) do
        nil ->
          raise RuntimeError,
            message: "executable not found in PATH: #{command_name_or_path}"

        resolved_command_path ->
          resolved_command_path
      end
    end
  end

  defp resolve_explicit_command_path!(explicit_command_path, true) do
    if has_windows_exec_ext?(explicit_command_path) and File.exists?(explicit_command_path) do
      explicit_command_path
    else
      resolve_windows_executable_path!(explicit_command_path)
    end
  end

  defp resolve_explicit_command_path!(explicit_command_path, false) do
    if File.exists?(explicit_command_path) do
      explicit_command_path
    else
      raise RuntimeError, message: "executable not found at #{explicit_command_path}"
    end
  end

  defp resolve_windows_executable_path!(explicit_command_path) do
    if resolved_path = find_windows_wrapper(explicit_command_path) do
      resolved_path
    else
      if File.exists?(explicit_command_path) do
        explicit_command_path
      else
        raise RuntimeError, message: "executable not found at #{explicit_command_path}"
      end
    end
  end
end
