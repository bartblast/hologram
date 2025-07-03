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
      else
        IO.puts("⚠️  No benchmark results found (no 'Formatting results...' marker)")
      end
    else
      IO.puts("❌ Benchmark failed with exit code: #{exit_code}")
      IO.puts("📋 Error output:")
      IO.puts(output)
    end
  rescue
    error ->
      IO.puts("❌ Error running benchmark: #{inspect(error)}")
  end

  IO.puts("")

  print_divider.()
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

benchmark_files
|> Enum.with_index(1)
|> Enum.each(fn {file_path, index} ->
  run_single_benchmark.(file_path, index, benchmark_count)
end)

IO.puts("✅ All benchmarks completed!")
IO.puts("")
