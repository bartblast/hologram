defmodule Hologram.Migration.CallCheck do
  @moduledoc false

  # What a migration does to a row must never change after it is applied, so its code
  # may call only what does not change with the app: its own functions and the Elixir and
  # Erlang/OTP standard libraries. A call to one of the app's modules, a dependency's or
  # Hologram's would change whenever they do.
  #
  # Code that ran while the module compiled - a call in the module body, another module's
  # macro - left only its results in the bytecode, so it is checked through the modules the
  # compiler recorded the migration using at compile time. The record can't tell a module
  # called from one only named, so reading an attribute holding MyApp.Task in the body - as
  # an op that reads it does - is refused too; a module named in an op itself, or held in an
  # attribute only a function reads, is not used at compile time. The record covers the
  # whole file, so a second module in a migration file is checked along with it.
  #
  # Known blind spots: a call whose module is known only at runtime (apply/3, mod.fun())
  # names no module here; a module-body call to Hologram.Migration cannot be told apart from
  # the use that requires it; and a standard-library call that reads the environment
  # (Application.get_env/2, System.get_env/1) passes, though its value can differ per build.

  # Elixir's applications a release ships - the others (Mix, ExUnit, IEx) are absent from
  # one, so a call to them fails at runtime anyway.
  @elixir_apps [:eex, :elixir, :logger]

  @doc """
  Validates that the compiled migration module given by its env and bytecode references
  no module outside the standard libraries - no remote call, function capture or struct
  literal names one, and the module neither requires one nor used one while it compiled,
  `Hologram.Migration` aside, which its `use` requires. Returns :ok, or raises
  Hologram.CompileError naming each reference, with its line where it has one.

  Reads the module's debug info, which `use Hologram.Migration` keeps for every migration
  module.
  """
  @spec validate!(Macro.Env.t(), binary) :: :ok
  def validate!(env, bytecode) do
    file = Path.relative_to_cwd(env.file)

    code_references =
      bytecode
      |> definitions!(env.module, file)
      |> collect_references()

    # A module the code names already has a line to show, which says more.
    code_modules = MapSet.new(code_references, fn {module, _line} -> module end)

    compile_time_references =
      env.requires
      |> Enum.concat(compile_time_modules(env))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == Hologram.Migration or MapSet.member?(code_modules, &1)))
      |> Enum.map(&{&1, nil})

    references = Enum.uniq(code_references ++ compile_time_references)
    refused_modules = refused_modules(references, env.module)

    refused =
      references
      |> Enum.filter(fn {module, _line} -> Map.has_key?(refused_modules, module) end)
      |> Enum.sort_by(fn {module, line} -> {line || 0, inspect(module)} end)

    if refused != [] do
      raise Hologram.CompileError, message: refusal_message(refused, refused_modules, file)
    end

    :ok
  end

  defp collect_references(definitions) do
    {_ast, references} =
      Macro.prewalk(definitions, [], fn
        {{:., meta, [module, _fun]}, _call_meta, _args} = node, acc when is_atom(module) ->
          {node, [{module, meta[:line]} | acc]}

        {:%, meta, [module, _fields]} = node, acc when is_atom(module) ->
          {node, [{module, meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    references
  end

  # The modules the compiler recorded the migration using while it compiled - for a call or
  # a macro - and those whose exports it depends on, like a struct's. Kernel.LexicalTracker is
  # Elixir's internal record of them, alive until the file is compiled; a test pins its shape,
  # so an Elixir release that changes it fails Hologram's own suite rather than turning the
  # check off quietly.
  defp compile_time_modules(env) do
    with tracker when is_pid(tracker) <- env.lexical_tracker,
         true <- Process.alive?(tracker),
         true <- function_exported?(Kernel.LexicalTracker, :references, 1),
         references when is_tuple(references) and tuple_size(references) >= 2 <-
           Kernel.LexicalTracker.references(tracker) do
      elem(references, 0) ++ elem(references, 1)
    else
      _unavailable -> []
    end
  end

  defp definitions!(bytecode, module, file) do
    with {:ok, {_module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(bytecode, [:debug_info]),
         {:ok, %{definitions: definitions}} <- backend.debug_info(:elixir_v1, module, data, []) do
      # A clause is a 4-tuple, which the AST walk would not enter, so its parts are taken out.
      Enum.flat_map(definitions, fn {_name_arity, _kind, _meta, clauses} ->
        Enum.map(clauses, fn {_clause_meta, args, guards, body} -> [args, guards, body] end)
      end)
    else
      # Unreachable while use Hologram.Migration sets @compile {:debug_info, true}, which
      # wins over the project's option and the module's own.
      _error ->
        raise Hologram.CompileError,
          message: "#{file} has no debug info, so the calls it makes cannot be checked"
    end
  end

  defp expand_dir(dir) do
    dir
    |> to_string()
    |> Path.expand()
  end

  defp refusal_message(refused, refused_modules, file) do
    lines =
      Enum.map_join(refused, "\n", fn {module, line} ->
        location = if line, do: "#{file}:#{line}", else: file
        moment = if line, do: "", else: " at compile time"

        suffix =
          if refused_modules[module] == :missing,
            do: ", which is not compiled yet or cannot be found",
            else: ""

        "  #{location} - uses #{inspect(module)}#{moment}#{suffix}"
      end)

    hint =
      if Enum.any?(refused, fn {_module, line} -> is_nil(line) end),
        do:
          "\nAn op reading an attribute that holds a module uses the module at compile " <>
            "time - if that is the case here, write the module in the op itself.",
        else: ""

    "a migration may use only its own functions and the Elixir and Erlang/OTP standard " <>
      "libraries - what it does to rows must never change after it is applied, and the " <>
      "app's, its dependencies' and Hologram's modules change with them:\n" <> lines <> hint
  end

  # Each module is judged once, however often the migration names it: the refused ones map
  # to why - :missing for a module the code path does not hold (yet: in a fresh build, an
  # app module the compiler has not reached is not there), :outside for the rest.
  defp refused_modules(references, migration) do
    standard_dirs = standard_library_dirs()

    references
    |> Enum.map(fn {module, _line} -> module end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == migration))
    |> Enum.flat_map(fn module ->
      case standing(module, standard_dirs) do
        :standard -> []
        reason -> [{module, reason}]
      end
    end)
    |> Map.new()
  end

  defp standard_library_dirs do
    elixir_dirs =
      Enum.flat_map(@elixir_apps, fn app ->
        case :code.lib_dir(app) do
          dir when is_list(dir) -> [expand_dir(dir)]
          {:error, :bad_name} -> []
        end
      end)

    [expand_dir(:code.root_dir()) | elixir_dirs]
  end

  # An Elixir protocol is judged by its application rather than its path: once Mix has
  # consolidated protocols, a VM that is already running - a code reloader, an IEx
  # recompile, a test run - loads them from the project's build dir.
  defp standing(module, standard_dirs) do
    case :code.which(module) do
      :preloaded ->
        :standard

      path when is_list(path) ->
        expanded_path = expand_dir(path)

        if elixir_app_module?(module) or
             Enum.any?(standard_dirs, &String.starts_with?(expanded_path, &1 <> "/")) do
          :standard
        else
          :outside
        end

      :non_existing ->
        :missing

      _cover_compiled ->
        :outside
    end
  end

  defp elixir_app_module?(module) do
    case :application.get_application(module) do
      {:ok, app} -> app in @elixir_apps
      :undefined -> false
    end
  end
end
