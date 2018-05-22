defmodule PhoenixDemoWeb.PageController do
  use PhoenixDemoWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
