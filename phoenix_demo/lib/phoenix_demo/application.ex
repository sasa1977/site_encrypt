defmodule PhoenixDemo.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PhoenixDemo.PubSub},
      {SiteEncrypt.Phoenix, {PhoenixDemoWeb.Certbot, PhoenixDemoWeb.Endpoint}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    PhoenixDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
