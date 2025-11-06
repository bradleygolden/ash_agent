import Config

# Import environment-specific config
if config_env() == :test do
  import_config "test.exs"
end
