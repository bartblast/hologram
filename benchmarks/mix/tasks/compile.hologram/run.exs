alias Hologram.Commons.FileUtils
alias Hologram.Reflection

Benchee.run(
  %{
    "no cache" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_each: fn {benchmark_tmp_dir, lib_package_json_path, benchmark_assets_dir,
                        benchmark_package_json_path, opts} ->
         FileUtils.recreate_dir(benchmark_tmp_dir)
         File.mkdir!(benchmark_assets_dir)
         File.cp!(lib_package_json_path, benchmark_package_json_path)

         opts
       end},
    "has cache" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_scenario: fn {benchmark_tmp_dir, lib_package_json_path, benchmark_assets_dir,
                            benchmark_package_json_path, opts} ->
         FileUtils.recreate_dir(benchmark_tmp_dir)
         File.mkdir!(benchmark_assets_dir)
         File.cp!(lib_package_json_path, benchmark_package_json_path)

         Mix.Tasks.Compile.Hologram.run(opts)

         opts
       end}
  },
  before_scenario: fn _input ->
    benchmark_tmp_dir = Path.join([Reflection.tmp_dir(), "benchmarks", "mix", "compile.hologram"])

    lib_assets_dir = Path.join(Reflection.root_dir(), "assets")
    lib_package_json_path = Path.join(lib_assets_dir, "package.json")

    benchmark_assets_dir = Path.join(benchmark_tmp_dir, "assets")
    benchmark_package_json_path = Path.join(benchmark_assets_dir, "package.json")

    node_modules_path = Path.join(benchmark_assets_dir, "node_modules")

    opts = [
      assets_dir: benchmark_assets_dir,
      build_dir: Path.join(benchmark_tmp_dir, "build"),
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      formatter_bin_path: Path.join([node_modules_path, ".bin", "biome"]),
      js_dir: Path.join(lib_assets_dir, "js"),
      static_dir: Path.join(benchmark_tmp_dir, "static"),
      tmp_dir: Path.join(benchmark_tmp_dir, "tmp")
    ]

    {benchmark_tmp_dir, lib_package_json_path, benchmark_assets_dir, benchmark_package_json_path,
     opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "mix compile.hologram", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
