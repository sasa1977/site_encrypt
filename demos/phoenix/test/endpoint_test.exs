defmodule PhoenixDemo.EndpointTest do
  use ExUnit.Case, async: false

  test "certification" do
    SiteEncrypt.Phoenix.Test.verify_certification(PhoenixDemo.Endpoint, [
      ~U[2020-01-01 00:00:00Z],
      ~U[2020-02-01 00:00:00Z]
    ])
  end
end
