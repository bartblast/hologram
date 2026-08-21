defmodule Hologram.CompileError do
  @moduledoc """
  Raised when a page or a component can't be compiled.

  The error is raised while sweeping modules that are already compiled, so the BEAM
  stacktrace it carries names the framework rather than the code the developer wrote.
  The file, the line and the path through the developer's own functions are carried
  here instead, and rendered into the message. All three are optional - an error
  carrying none of them reads exactly as its message.
  """

  defexception [:message, :file, :line, :stack]

  @typedoc """
  A frame of the path an error was reached through, in the shape Elixir's own
  stacktrace entries take, so that it renders and is read like one.
  """
  @type frame :: {module, atom, arity, keyword}

  @impl Exception
  def message(%__MODULE__{message: message} = error) do
    location(error) <> message <> frames(error)
  end

  defp frames(%__MODULE__{stack: stack}) when stack in [nil, []], do: ""

  defp frames(%__MODULE__{stack: stack}) do
    "\n" <> Enum.map_join(stack, "\n", &("    " <> Exception.format_stacktrace_entry(&1)))
  end

  defp location(%__MODULE__{file: nil}), do: ""

  defp location(%__MODULE__{file: file, line: nil}), do: "#{Path.relative_to_cwd(file)}: "

  defp location(%__MODULE__{file: file, line: line}) do
    "#{Path.relative_to_cwd(file)}:#{line}: "
  end
end
