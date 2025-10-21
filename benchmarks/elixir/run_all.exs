# credo:disable-for-this-file Credo.Check.Refactor.IoPuts

# Run in the project root dir:
# $ mix run benchmarks/elixir/run_all.exs

defmodule BenchmarkRunner do
  @moduledoc false

  @benchmarks_dir "benchmarks/elixir"

  @doc """
  Main entry point to run all benchmarks.
  """
  @spec run :: :ok
  def run do
    IO.puts("")
    IO.puts("🚀 Starting benchmark execution...")
    IO.puts("📁 Scanning #{@benchmarks_dir} for benchmark scripts...")

    benchmark_files = find_benchmark_files()
    IO.puts("📊 Found #{length(benchmark_files)} benchmark scripts")

    print_divider()

    results = execute_benchmarks(benchmark_files)

    IO.puts("✅ All benchmarks completed!")

    write_readme(results)

    IO.puts("")
  end

  defp count_by_status(results, status) do
    Enum.count(results, fn {result_status, _name, _data} -> result_status == status end)
  end

  defp execute_benchmarks(benchmark_files) do
    benchmark_count = length(benchmark_files)

    benchmark_files
    |> Enum.with_index(1)
    |> Enum.map(fn {file_path, index} ->
      run_single_benchmark(file_path, index, benchmark_count)
    end)
  end

  defp find_benchmark_files do
    @benchmarks_dir
    |> Path.join("**/run.exs")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp format_benchmark_name(file_path) do
    file_path
    |> Path.dirname()
    |> Path.relative_to("benchmarks/elixir")
    |> String.replace("/", " → ")
    |> String.replace(".", "root")
  end

  defp format_result({:ok, name, stats}) do
    """
    ### ✅ #{name}

    ```
    #{stats}
    ```

    """
  end

  defp format_result({:warning, name, message}) do
    """
    ### ⚠️  #{name}

    #{message}

    """
  end

  defp format_result({:error, name, message}) do
    """
    ### ❌ #{name}

    #{message}

    """
  end

  defp handle_benchmark_result(output, exit_code, benchmark_name) do
    if exit_code == 0 do
      IO.puts("✅ Benchmark completed successfully")
      IO.puts("")

      # Extract and show only the benchmark results after "Formatting results..."
      benchmark_stats =
        case String.split(output, "Formatting results...") do
          [_before, stats] -> String.trim(stats)
          _fallback -> nil
        end

      if benchmark_stats do
        IO.puts("📊 Benchmark Results:")
        IO.puts(benchmark_stats)
        {:ok, benchmark_name, benchmark_stats}
      else
        IO.puts("⚠️  No benchmark results found (no 'Formatting results...' marker)")
        {:warning, benchmark_name, "No benchmark results found"}
      end
    else
      IO.puts("❌ Benchmark failed with exit code: #{exit_code}")
      IO.puts("📋 Error output:")
      IO.puts(output)
      {:error, benchmark_name, "Failed with exit code: #{exit_code}"}
    end
  end

  defp print_divider do
    "-"
    |> String.duplicate(80)
    |> IO.puts()
  end

  defp run_single_benchmark(file_path, index, count) do
    benchmark_name = format_benchmark_name(file_path)

    IO.puts("")
    IO.puts("🔄 [#{index}/#{count}] Running: #{benchmark_name}")
    IO.puts("📄 File: #{file_path}")

    result =
      try do
        {output, exit_code} =
          System.cmd("mix", ["run", file_path],
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "dev"}]
          )

        handle_benchmark_result(output, exit_code, benchmark_name)
      rescue
        error ->
          error_msg = "Error running benchmark: #{inspect(error)}"
          IO.puts("❌ #{error_msg}")
          {:error, benchmark_name, error_msg}
      end

    IO.puts("")
    print_divider()

    result
  end

  defp write_readme(results) do
    timestamp = DateTime.to_string(DateTime.utc_now())

    intro_content = """
    # Elixir Benchmarks

    Last run: #{timestamp}

    ## Summary

    Total benchmarks: #{length(results)}
    Successful: #{count_by_status(results, :ok)}
    Warnings: #{count_by_status(results, :warning)}
    Failed: #{count_by_status(results, :error)}

    ## Results

    """

    results_content = Enum.map_join(results, "\n", &format_result/1)

    readme_path = Path.join(@benchmarks_dir, "README.md")
    File.write!(readme_path, intro_content <> results_content)

    IO.puts("📝 Summary written to #{readme_path}")
  end
end

BenchmarkRunner.run()
