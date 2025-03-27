alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Reflection

lib_package_json_path = Path.join([Reflection.root_dir(), "assets", "package.json"])

Benchee.run(
  %{
    "no install" =>
      {fn {assets_dir, build_dir} ->
         Compiler.maybe_install_js_deps(assets_dir, build_dir)
       end,
       before_scenario: fn _input ->
         tmp_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_install_js_deps_no_install_2"
           ])

         assets_dir = Path.join(tmp_dir, "assets")
         build_dir = Path.join(tmp_dir, "build")
         package_json_path = Path.join(assets_dir, "package.json")

         FileUtils.recreate_dir(tmp_dir)
         File.mkdir!(assets_dir)
         File.mkdir!(build_dir)
         File.cp!(lib_package_json_path, package_json_path)

         Compiler.maybe_install_js_deps(assets_dir, build_dir)

         {assets_dir, build_dir}
       end},
    "do install" =>
      {fn {assets_dir, build_dir} ->
         Compiler.maybe_install_js_deps(assets_dir, build_dir)
       end,
       before_scenario: fn _input ->
         tmp_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_install_js_deps_do_install_2"
           ])

         assets_dir = Path.join(tmp_dir, "assets")
         build_dir = Path.join(tmp_dir, "build")
         package_json_path = Path.join(assets_dir, "package.json")

         {tmp_dir, assets_dir, build_dir, package_json_path}
       end,
       before_each: fn {tmp_dir, assets_dir, build_dir, package_json_path} ->
         FileUtils.recreate_dir(tmp_dir)
         File.mkdir!(assets_dir)
         File.mkdir!(build_dir)
         File.cp!(lib_package_json_path, package_json_path)

         System.cmd("npm", ["cache", "clean", "--force"])

         {assets_dir, build_dir}
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.maybe_install_js_deps/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
