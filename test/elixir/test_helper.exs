# Create tmp dir if it doesn't exist yet.
tmp_path = "#{File.cwd!()}/tmp"
File.mkdir_p!(tmp_path)

ExUnit.start()
