defmodule Mix.Tasks.Holo.Compiler.PageExFunSizes do
  @moduledoc """
  Calculates the JavaScript size of each Elixir function that is included in the specified page module bundle.
  The results are sorted by size.

  ## Examples

      $ mix holo.compiler.page_ex_fun_sizes MyPageModule 

  Where `MyPageModule` is the name of the page module you want to analyze (without the `Elixir.` prefix).
  """

  use Mix.Task

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([page_module_name]) do
    page_module = String.to_existing_atom("Elixir." <> page_module_name)
    ir_plt = Compiler.build_ir_plt()
    aggregated_funs = aggregate_funs(ir_plt)

    ir_plt
    |> build_call_graph()
    |> CallGraph.list_page_mfas(page_module)
    |> filter_elixir_mfas()
    |> calculate_encoded_fun_sizes(aggregated_funs)
    |> sort_by_size_and_mfa()
    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    |> IO.inspect(limit: :infinity)

    :ok
  end

  defp aggregate_funs(ir_plt) do
    ir_plt
    |> PLT.get_all()
    |> Enum.reduce(%{}, fn {module, module_def_ir}, acc ->
      module_def_ir
      |> IR.aggregate_module_funs()
      |> Enum.reduce(acc, fn {{function, arity}, fun_data}, module_acc ->
        Map.put(module_acc, {module, function, arity}, fun_data)
      end)
    end)
  end

  defp build_call_graph(ir_plt) do
    ir_plt
    |> Compiler.build_call_graph()
    |> CallGraph.remove_manually_ported_mfas()
    |> remove_runtime_mfas()
  end

  defp calculate_encoded_fun_sizes(mfas, aggregated_funs) do
    context = %Context{}

    Enum.reduce(mfas, [], fn {module, fun, arity} = mfa, acc ->
      case aggregated_funs[mfa] do
        {visibility, clauses} ->
          module_name = Reflection.module_name(module)

          output =
            Encoder.encode_elixir_function(module_name, fun, arity, visibility, clauses, context)

          [{mfa, String.length(output)} | acc]

        _fallback ->
          acc
      end
    end)
  end

  defp filter_elixir_mfas(mfas) do
    Enum.filter(mfas, fn {module, _fun, _arity} -> Reflection.elixir_module?(module) end)
  end

  defp remove_runtime_mfas(call_graph) do
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)
  end

  defp sort_by_size_and_mfa(encoded_fun_sizes) do
    Enum.sort(encoded_fun_sizes, fn {mfa_1, size_1}, {mfa_2, size_2} ->
      cond do
        size_1 > size_2 -> true
        size_1 == size_2 && mfa_1 < mfa_2 -> true
        true -> false
      end
    end)
  end
end
