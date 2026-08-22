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

  # A blank line sets the path apart from the message, which runs long - a build refusal explains
  # itself in a sentence or two, and the frames below it are a different kind of reading.
  defp frames(%__MODULE__{stack: stack}) when stack in [nil, []], do: ""

  defp frames(%__MODULE__{stack: stack}) do
    "\n\n" <>
      Enum.map_join(stack, "\n", &("    " <> Exception.format_stacktrace_entry(located(&1))))
  end

  # Every path this renders is relative, the frames like the prefix - a frame is built from what a
  # module records as its source, which is absolute, and an absolute path names the machine it was
  # built on rather than the project. A frame whose file is unknown renders as the function alone.
  defp located({module, function, arity, location}) do
    case Keyword.fetch(location, :file) do
      {:ok, nil} -> {module, function, arity, Keyword.delete(location, :file)}
      {:ok, file} -> {module, function, arity, Keyword.put(location, :file, relative(file))}
      :error -> {module, function, arity, location}
    end
  end

  defp location(%__MODULE__{file: nil}), do: ""

  defp location(%__MODULE__{file: file, line: nil}), do: "#{relative(file)}: "

  defp location(%__MODULE__{file: file, line: line}), do: "#{relative(file)}:#{line}: "

  defp relative(file), do: Path.relative_to_cwd(file)
end
