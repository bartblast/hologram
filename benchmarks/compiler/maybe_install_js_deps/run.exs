alias Hologram.Commons.FileUtils
alias Hologram.Commons.Reflection
alias Hologram.Compiler

lib_package_json_path = Path.join([Reflection.root_dir(), "assets", "package.json"])

# Setup "no install" case

no_install_tmp_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_install_js_deps_no_install"])

no_install_assets_dir = Path.join(no_install_tmp_dir, "assets")
no_install_build_dir = Path.join(no_install_tmp_dir, "build")
no_install_package_json_path = Path.join(no_install_assets_dir, "package.json")

FileUtils.recreate_dir(no_install_tmp_dir)
File.mkdir!(no_install_assets_dir)
File.mkdir!(no_install_build_dir)

File.cp!(lib_package_json_path, no_install_package_json_path)

Compiler.maybe_install_js_deps(no_install_assets_dir, no_install_build_dir)

# Setup "do install" case

do_install_tmp_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_install_js_deps_do_install"])

do_install_assets_dir = Path.join(do_install_tmp_dir, "assets")
do_install_build_dir = Path.join(do_install_tmp_dir, "build")
do_install_package_json_path = Path.join(do_install_assets_dir, "package.json")

Benchee.run(
  %{
    "no install" => fn ->
      Compiler.maybe_install_js_deps(no_install_assets_dir, no_install_build_dir)
    end,
    "do install" =>
      {fn _input ->
         Compiler.maybe_install_js_deps(do_install_assets_dir, do_install_build_dir)
       end,
       before_each: fn _input ->
         FileUtils.recreate_dir(do_install_tmp_dir)
         File.mkdir!(do_install_assets_dir)
         File.mkdir!(do_install_build_dir)

         File.cp!(lib_package_json_path, do_install_package_json_path)

         System.cmd("npm", ["cache", "clean", "--force"])
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_install_js_deps/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
