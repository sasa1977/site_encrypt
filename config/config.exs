import Config

config :phoenix, json_library: Jason

if Mix.env() == :test do
  config :logger, level: :warning
end
