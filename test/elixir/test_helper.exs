# Create tmp dir if it doesn't exist yet.
"#{File.cwd!()}/tmp" |> File.mkdir_p!()

ExUnit.start()
