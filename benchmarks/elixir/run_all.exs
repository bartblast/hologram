# credo:disable-for-this-file Credo.Check.Refactor.IoPuts

# Run in the project root dir:
# $ mix run benchmarks/elixir/run_all.exs

benchmarks_dir = "benchmarks/elixir"

print_divider = fn ->
  "-"
  |> String.duplicate(80)
  |> IO.puts()
end

run_single_benchmark = fn file_path, index, count ->
  benchmark_name =
    file_path
    |> Path.dirname()
    |> Path.relative_to("benchmarks/elixir")
    |> String.replace("/", " → ")
    |> String.replace(".", "root")

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
    rescue
      error ->
        error_msg = "Error running benchmark: #{inspect(error)}"
        IO.puts("❌ #{error_msg}")
        {:error, benchmark_name, error_msg}
    end

  IO.puts("")
  print_divider.()

  result
end

write_readme = fn results, benchmarks_dir ->
  timestamp = DateTime.to_string(DateTime.utc_now())

  intro_content = """
  # Elixir Benchmarks

  Last run: #{timestamp}

  ## Summary

  Total benchmarks: #{length(results)}
  Successful: #{Enum.count(results, fn {status, _name, _stats} -> status == :ok end)}
  Warnings: #{Enum.count(results, fn {status, _name, _message} -> status == :warning end)}
  Failed: #{Enum.count(results, fn {status, _name, _message} -> status == :error end)}

  ## Results

  """

  results_content =
    results
    |> Enum.map(fn
      {:ok, name, stats} ->
        """
        ### ✅ #{name}

        ```
        #{stats}
        ```

        """

      {:warning, name, message} ->
        """
        ### ⚠️  #{name}

        #{message}

        """

      {:error, name, message} ->
        """
        ### ❌ #{name}

        #{message}

        """
    end)
    |> Enum.join("\n")

  readme_path = Path.join(benchmarks_dir, "README.md")
  File.write!(readme_path, intro_content <> results_content)

  IO.puts("📝 Summary written to #{readme_path}")
end

IO.puts("")
IO.puts("🚀 Starting benchmark execution...")
IO.puts("📁 Scanning #{benchmarks_dir} for benchmark scripts...")

benchmark_files =
  benchmarks_dir
  |> Path.join("**/run.exs")
  |> Path.wildcard()
  |> Enum.sort()

IO.puts("📊 Found #{length(benchmark_files)} benchmark scripts")

print_divider.()

benchmark_count = length(benchmark_files)

results =
  benchmark_files
  |> Enum.with_index(1)
  |> Enum.map(fn {file_path, index} ->
    run_single_benchmark.(file_path, index, benchmark_count)
  end)

IO.puts("✅ All benchmarks completed!")
IO.puts("")

write_readme.(results, benchmarks_dir)
